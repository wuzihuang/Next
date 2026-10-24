package com.nextbody.hoop.features.profile

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.unit.dp
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.Fmt
import com.nextbody.hoop.services.Iso
import com.nextbody.hoop.services.SupabaseClient
import com.nextbody.hoop.services.optBoolOrNull
import com.nextbody.hoop.services.objOrNull
import com.nextbody.hoop.services.optStringOrNull
import com.nextbody.hoop.ui.Hairline
import com.nextbody.hoop.ui.HoldHaptics
import com.nextbody.hoop.ui.cardSkin
import com.nextbody.hoop.ui.hotZoneTap
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.Instant

/**
 * ADR 0032 · ChatGPT, Claude, Cursor or Grok reading this account's own data over MCP. This is
 * the outside-assistant connector, not the in-app AI — it stays on while AIFeature is off.
 *
 * The address carries no key. Each assistant signs in through mcp.nextbody.ai and gets its own
 * OAuth grant, so there is nothing secret to copy and every assistant can be cut off on its own.
 * Two records make a connection: Supabase Auth's grant (the refresh token) and our `mcp_grants`
 * row (what the gate checks on every request). Disconnecting removes both, the Auth grant first —
 * the other order leaves a grant that skips consent and then is refused.
 */
object AssistantsAddress {
    const val address = "https://mcp.nextbody.ai/mcp"
}

data class AssistantConnection(
    val id: String,
    var name: String,
    var canWrite: Boolean,
    var active: Boolean,
    var since: Instant?,
    var lastUsed: Instant?,
)

@Composable
fun AssistantsSheet(close: () -> Unit) {
    val scope = rememberCoroutineScope()
    val clipboard = LocalClipboardManager.current
    val connections = remember { mutableStateListOf<AssistantConnection>() }
    var loading by remember { mutableStateOf(true) }
    var loadFailed by remember { mutableStateOf(false) }
    var copied by remember { mutableStateOf(false) }
    val busy = remember { mutableStateListOf<String>() }
    var actionFailed by remember { mutableStateOf(false) }

    /**
     * Union of the two records. An Auth grant with no live row is shown paused; a live row whose
     * Auth grant is gone still holds an access token for up to an hour, so it stays listed until
     * it is disconnected here.
     */
    suspend fun load() {
        loading = connections.isEmpty()
        loadFailed = false
        try {
            val (grants, rows) = coroutineScope {
                val a = async { SupabaseClient.oauthGrants() }
                val b = async {
                    SupabaseClient.select("mcp_grants", listOf(
                        "select" to "client_id,client_name,can_write,granted_at,revoked_at,last_used_at"))
                }
                a.await() to b.await()
            }
            val merged = LinkedHashMap<String, AssistantConnection>()
            for (grant in grants) {
                val client = grant.objOrNull("client")
                val id = client?.optStringOrNull("id") ?: grant.optStringOrNull("client_id") ?: continue
                val name = client?.optStringOrNull("name") ?: grant.optStringOrNull("client_name") ?: id
                val since = grant.optStringOrNull("granted_at")?.let { Iso.parse(it) }
                merged[id] = AssistantConnection(id, name, canWrite = false, active = false, since = since, lastUsed = null)
            }
            for (row in rows) {
                val id = row.optStringOrNull("client_id") ?: continue
                if (row.optStringOrNull("revoked_at") != null) continue
                val c = merged[id] ?: AssistantConnection(id, id, false, false, null, null)
                row.optStringOrNull("client_name")?.takeIf { it.isNotEmpty() }?.let { c.name = it }
                c.canWrite = row.optBoolOrNull("can_write") ?: false
                c.active = true
                c.since = c.since ?: row.optStringOrNull("granted_at")?.let { Iso.parse(it) }
                c.lastUsed = row.optStringOrNull("last_used_at")?.let { Iso.parse(it) }
                merged[id] = c
            }
            connections.clear()
            connections.addAll(merged.values.sortedByDescending { it.lastUsed ?: it.since ?: Instant.MIN })
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (e: Exception) {
            loadFailed = true
        }
        loading = false
    }

    suspend fun setWrite(c: AssistantConnection, value: Boolean) {
        busy.add(c.id)
        try {
            SupabaseClient.rpc("set_mcp_grant_write", mapOf("p_client_id" to c.id, "p_can_write" to value))
            val i = connections.indexOfFirst { it.id == c.id }
            if (i >= 0) connections[i] = connections[i].copy(canWrite = value)
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (e: Exception) {
            actionFailed = true
        } finally {
            busy.remove(c.id)
        }
    }

    suspend fun disconnect(c: AssistantConnection) {
        busy.add(c.id)
        try {
            SupabaseClient.revokeOAuthGrant(c.id)
            SupabaseClient.rpc("revoke_mcp_grant", mapOf("p_client_id" to c.id))
            connections.removeAll { it.id == c.id }
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (e: Exception) {
            actionFailed = true
        } finally {
            busy.remove(c.id)
        }
    }

    LaunchedEffect(Unit) { load() }

    SheetFrame(title = L("AI assistants"), footer = { LimePill(L("Done")) { close() } }) {
        Column(
            Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState()).width(NB.Layout.contentWidth),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Text(
                L("Let ChatGPT, Claude, Cursor or Grok read your own NextBody data and log meals you describe. Add this address as a connector or MCP server, then sign in with this account."),
                style = NBFont.ui(400, 13.5f), color = NB.text1,
            )

            val copyLabel = L("Copy the MCP address")
            Row(
                Modifier
                    .width(NB.Layout.contentWidth)
                    .height(56.dp)
                    .cardSkin()
                    .hotZoneTap(pressedScale = 1f) {
                        clipboard.setText(AnnotatedString(AssistantsAddress.address))
                        HoldHaptics.release()
                        copied = true
                        scope.launch { delay(2_000); copied = false }
                    }
                    .semantics { contentDescription = copyLabel }
                    .padding(horizontal = 16.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("mcp.nextbody.ai/mcp", style = NBFont.dot(600, 13f).tracking(0.04f), color = NB.text1, maxLines = 1,
                    modifier = Modifier.weight(1f))
                Spacer(Modifier.width(24.dp)) // 12 + 0 + 12, as SwiftUI spaces around the Spacer
                Text(if (copied) L("COPIED") else L("COPY"), style = NBFont.dot(600, 11f).tracking(0.14f), color = NB.lime1)
            }

            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                ClientStep("CHATGPT", L("Settings › Apps & Connectors › Create. Paste the address."))
                ClientStep("CLAUDE", L("Settings › Connectors › Add custom connector. Paste the address."))
                ClientStep("CURSOR", L("Settings › MCP › Add server. Paste the address as the URL."))
                ClientStep("GROK", L("Settings › Connectors › Add MCP server. Paste the address."))
            }

            Text(L("CONNECTED"), style = NBFont.dot(600, 10f).tracking(0.14f), color = NB.text3Prod,
                modifier = Modifier.padding(top = 6.dp))

            when {
                loading -> Box(Modifier.width(NB.Layout.contentWidth).height(62.dp), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(Modifier.size(20.dp), color = NB.text3Prod, strokeWidth = 2.dp)
                }
                loadFailed -> Notice(L("Couldn't load connections. Tap to retry."), NB.ember1,
                    Modifier.hotZoneTap(pressedScale = 1f) { scope.launch { load() } })
                connections.isEmpty() -> Notice(L("Nothing connected yet."), NB.text3Prod)
                else -> Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    connections.forEach { c ->
                        ConnectionRow(c, working = c.id in busy,
                            onDisconnect = { scope.launch { disconnect(c) } },
                            onWrite = { v -> scope.launch { setWrite(c, v) } })
                    }
                }
            }

            Text(
                L("Assistants can read your metrics, sleep and meals. Logging meals is off until you turn it on for one. What an assistant reads is sent to its provider."),
                style = NBFont.ui(300, 12.5f).tracking(0.02f), color = NB.white.copy(alpha = 0.38f),
            )
        }
    }

    if (actionFailed) {
        AlertDialog(
            onDismissRequest = { actionFailed = false },
            confirmButton = {
                TextButton(onClick = { actionFailed = false }) { Text(L("OK"), color = NB.lime1) }
            },
            title = { Text(L("Couldn't update the connection"), style = NBFont.ui(500, 17f), color = NB.text1) },
            text = { Text(L("Check your connection and try again."), style = NBFont.ui(400, 13f), color = NB.text2) },
            containerColor = NB.carbon4,
        )
    }
}

@Composable
private fun Notice(text: String, tint: Color, modifier: Modifier = Modifier) {
    Box(
        modifier.width(NB.Layout.contentWidth).height(56.dp).cardSkin().padding(horizontal = 16.dp),
        contentAlignment = Alignment.CenterStart,
    ) {
        Text(text, style = NBFont.ui(400, 13f), color = tint)
    }
}

@Composable
private fun ConnectionRow(
    c: AssistantConnection,
    working: Boolean,
    onDisconnect: () -> Unit,
    onWrite: (Boolean) -> Unit,
) {
    Column(Modifier.width(NB.Layout.contentWidth).cardSkin().alpha(if (working) 0.5f else 1f)) {
        Row(
            Modifier.fillMaxWidth().height(62.dp).padding(horizontal = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(c.name, style = NBFont.ui(500, 14f).tracking(0.02f), color = NB.text1, maxLines = 1)
                Text(detail(c), style = NBFont.dot(500, 10f).tracking(0.14f), color = if (c.active) NB.text3Prod else NB.ember1)
            }
            Spacer(Modifier.width(0.dp))
            Text(L("DISCONNECT"), style = NBFont.dot(600, 10f).tracking(0.14f), color = NB.ember1,
                modifier = Modifier.hotZoneTap(enabled = !working, pressedScale = 1f, onClick = onDisconnect))
        }
        if (c.active) {
            Hairline(modifier = Modifier.padding(start = 16.dp))
            Row(
                Modifier.fillMaxWidth().height(62.dp).padding(horizontal = 16.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text(L("Log meals"), style = NBFont.ui(500, 14f).tracking(0.02f), color = NB.text1)
                    Text(L("WRITES TO YOUR FOOD LOG"), style = NBFont.dot(500, 10f).tracking(0.14f), color = NB.text3Prod)
                }
                Spacer(Modifier.width(16.dp))
                NBSwitch(c.canWrite, enabled = !working, onChange = onWrite)
            }
        }
    }
}

@Composable
private fun ClientStep(client: String, text: String) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(client, style = NBFont.dot(600, 10f).tracking(0.14f), color = NB.lime1,
            modifier = Modifier.width(64.dp).padding(top = 2.dp))
        Text(text, style = NBFont.ui(400, 13f), color = NB.text1, modifier = Modifier.weight(1f))
        Spacer(Modifier.width(0.dp))
    }
}

private fun detail(c: AssistantConnection): String {
    if (!c.active) return L("NOT ACTIVE · DISCONNECT TO RESET")
    c.lastUsed?.let { return L("LAST USED %@", Fmt.displayDate(it, "MMM d").uppercase()) }
    c.since?.let { return L("CONNECTED %@", Fmt.displayDate(it, "MMM d").uppercase()) }
    return L("CONNECTED")
}
