package com.nextbody.hoop.features.profile

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.net.Uri
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import com.nextbody.hoop.data.DataStore
import com.nextbody.hoop.data.DebugEdgeFlag
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.services.FeedbackReport
import com.nextbody.hoop.ui.hotZoneTap
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * 11 · REPORT A PROBLEM. A title, the words, up to three screenshots, one Send. It has exactly
 * one destination — an issue on the product repo, filed with the build and the phone so the
 * first reply is never "which version?".
 *
 * The form survives a failure: nothing is cleared until the server has answered with an issue
 * number. Sending is the only thing that leaves the phone.
 */
@Composable
fun FeedbackSheet(close: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val focus = LocalFocusManager.current
    val bodyFocus = remember { FocusRequester() }
    // `NB_DEBUG_EDGE=feedback_filled` walks the sheet with the form full.
    val filled = DebugEdgeFlag.on("feedback_filled")
    var title by remember { mutableStateOf(if (filled) "Sleep page shows —— after a full night" else "") }
    var body by remember {
        mutableStateOf(if (filled) "Wore the band all night, opened the app at 7:40, the sleep card is blank until I pull to refresh." else "")
    }
    val images = remember { mutableStateListOf<FeedbackReport.Image>() }
    var sending by remember { mutableStateOf(false) }
    var outcome by remember { mutableStateOf<FeedbackReport.Outcome?>(null) }

    val canSend = !sending && title.isNotBlank() && body.isNotBlank()

    val left = FeedbackReport.maxImages - images.size
    val picker = rememberLauncherForActivityResult(
        ActivityResultContracts.PickMultipleVisualMedia(FeedbackReport.maxImages),
    ) { uris: List<Uri> ->
        if (uris.isEmpty()) return@rememberLauncherForActivityResult
        scope.launch {
            for (uri in uris) {
                if (images.size >= FeedbackReport.maxImages) break
                val prepared = withContext(Dispatchers.Default) {
                    decode(context, uri)?.let { FeedbackReport.Image.prepare(it) }
                } ?: continue
                images.add(prepared)
            }
        }
    }

    fun send() {
        if (!canSend) return
        focus.clearFocus()
        sending = true
        outcome = null
        val t = title.trim()
        val b = body.trim()
        val imgs = images.toList()
        val band = DataStore.band
        scope.launch {
            val result = FeedbackReport.send(t, b, imgs, bandConnected = band.connected,
                firmware = band.firmware, batteryPercent = band.batteryPercent)
            sending = false
            outcome = result
        }
    }

    val filed = (outcome as? FeedbackReport.Outcome.Filed)?.filed
    SheetFrame(
        title = L("Report a problem"),
        footer = {
            if (filed != null) {
                LimePill(L("Done")) { close() }
            } else {
                LimePill(if (sending) L("SENDING …") else L("Send"), enabled = canSend) { send() }
            }
        },
    ) {
        if (filed != null) {
            Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(6.dp).background(NB.lime1, CircleShape))
                    Text(L("FILED"), style = NBFont.dot(600, 10f).tracking(0.2f), color = NB.lime1)
                }
                Text(
                    L("Filed as #%@. Thank you — we read every one.", filed.number.toString()),
                    style = NBFont.brand(400, 14f).copy(lineHeight = spaced(14f, 7f)), color = NB.text2,
                )
                Box(
                    Modifier
                        .fillMaxWidth()
                        .heightIn(min = 56.dp)
                        .background(NB.carbon4, RoundedCornerShape(NB.R.chip))
                        .border(1.dp, NB.hairline, RoundedCornerShape(NB.R.chip))
                        .padding(horizontal = 16.dp),
                    contentAlignment = Alignment.CenterStart,
                ) {
                    Text(title, style = NBFont.ui(500, 16f).tracking(0.01f), color = NB.text1)
                }
            }
        } else {
            Column(
                Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState()).padding(bottom = 8.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                FieldBox(L("Title"), title, { title = it }, imeAction = ImeAction.Next,
                    onSubmit = { runCatching { bodyFocus.requestFocus() } })

                // The description is the one field allowed to grow. Same chip as FieldBox, taller.
                Box(
                    Modifier
                        .fillMaxWidth()
                        .background(NB.carbon4, RoundedCornerShape(NB.R.chip))
                        .border(1.dp, NB.hairline, RoundedCornerShape(NB.R.chip)),
                ) {
                    if (body.isEmpty()) {
                        Text(
                            L("What happened, and what you expected instead."),
                            style = NBFont.ui(400, 15f), color = NB.white.copy(alpha = 0.28f),
                            modifier = Modifier.padding(start = 21.dp, end = 21.dp, top = 22.dp),
                        )
                    }
                    BasicTextField(
                        value = body,
                        onValueChange = { body = it },
                        textStyle = NBFont.ui(400, 15f).copy(color = NB.text1),
                        cursorBrush = SolidColor(NB.lime1),
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(min = 132.dp)
                            .padding(start = 21.dp, end = 21.dp, top = 22.dp, bottom = 22.dp)
                            .focusRequester(bodyFocus),
                    )
                }

                // Thumbnails first, the picker tile last. Three fills the row; the tile goes away.
                Column(Modifier.padding(top = 4.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(L("SCREENSHOTS · UP TO 3"), style = NBFont.dot(600, 10f).tracking(0.18f), color = NB.text2)
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        images.forEachIndexed { i, im ->
                            Box(Modifier.size(72.dp)) {
                                Image(
                                    im.preview.asImageBitmap(), contentDescription = null,
                                    contentScale = ContentScale.Crop,
                                    modifier = Modifier
                                        .size(72.dp)
                                        .clip(RoundedCornerShape(12.dp))
                                        .border(1.dp, NB.hairline, RoundedCornerShape(12.dp)),
                                )
                                Box(
                                    Modifier
                                        .align(Alignment.TopEnd)
                                        .offset(x = 6.dp, y = (-6).dp)
                                        .size(20.dp)
                                        .background(NB.lime1, CircleShape)
                                        .hotZoneTap(enabled = !sending, pressedScale = 1f) { images.removeAt(i) },
                                    contentAlignment = Alignment.Center,
                                ) {
                                    Canvas(Modifier.size(8.dp)) {
                                        val w = 1.8.dp.toPx()
                                        drawLine(NB.carbon, androidx.compose.ui.geometry.Offset(0f, 0f),
                                            androidx.compose.ui.geometry.Offset(size.width, size.height), w, StrokeCap.Round)
                                        drawLine(NB.carbon, androidx.compose.ui.geometry.Offset(size.width, 0f),
                                            androidx.compose.ui.geometry.Offset(0f, size.height), w, StrokeCap.Round)
                                    }
                                }
                            }
                        }
                        if (left > 0) {
                            Box(
                                Modifier
                                    .size(72.dp)
                                    .background(NB.carbon4, RoundedCornerShape(12.dp))
                                    .hotZoneTap(enabled = !sending, pressedScale = 1f) {
                                        picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                                    },
                                contentAlignment = Alignment.Center,
                            ) {
                                Canvas(Modifier.size(72.dp)) {
                                    val r = 12.dp.toPx()
                                    drawRoundRect(
                                        NB.lime1.copy(alpha = 0.4f), cornerRadius = CornerRadius(r, r),
                                        style = Stroke(width = 1.dp.toPx(),
                                            pathEffect = PathEffect.dashPathEffect(floatArrayOf(4.dp.toPx(), 3.dp.toPx()))),
                                    )
                                    val c = center
                                    val arm = 8.dp.toPx()
                                    val w = 1.8.dp.toPx()
                                    drawLine(NB.lime1, c.copy(x = c.x - arm), c.copy(x = c.x + arm), w)
                                    drawLine(NB.lime1, c.copy(y = c.y - arm), c.copy(y = c.y + arm), w)
                                }
                            }
                        }
                    }
                }

                Text(
                    L("Goes to the NEXTBODY issue tracker with your app version and phone model. No health data is attached."),
                    style = NBFont.ui(300, 12f).tracking(0.02f).copy(lineHeight = spaced(12f, 4f)),
                    color = NB.white.copy(alpha = 0.38f),
                    modifier = Modifier.padding(top = 4.dp),
                )

                val line = when (outcome) {
                    FeedbackReport.Outcome.Failed -> L("Could not reach the server. Nothing was sent — your words are still here.")
                    FeedbackReport.Outcome.Unconfigured -> L("Reporting is not set up on this server yet.")
                    FeedbackReport.Outcome.RateLimited -> L("Too many reports in a minute. Wait a moment and send again.")
                    else -> null
                }
                if (line != null) {
                    Text(line, style = NBFont.ui(400, 12f).tracking(0.02f).copy(lineHeight = spaced(12f, 4f)), color = NB.alert2)
                }
            }
        }
    }
}

private fun decode(context: android.content.Context, uri: Uri): Bitmap? = runCatching {
    if (Build.VERSION.SDK_INT >= 28) {
        ImageDecoder.decodeBitmap(ImageDecoder.createSource(context.contentResolver, uri)) { decoder, _, _ ->
            decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
        }
    } else {
        context.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it) }
    }
}.getOrNull()
