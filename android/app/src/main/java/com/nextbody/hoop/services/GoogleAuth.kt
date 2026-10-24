package com.nextbody.hoop.services

import android.app.Activity
import android.content.Context
import android.net.Uri
import androidx.browser.customtabs.CustomTabsIntent
import androidx.credentials.ClearCredentialStateRequest
import androidx.credentials.CredentialManager
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.GetCredentialException
import androidx.credentials.exceptions.NoCredentialException
import com.google.android.libraries.identity.googleid.GetGoogleIdOption
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import com.nextbody.hoop.BuildConfig

/**
 * 01 · the Google button on the gate. The account picker hands back a Google identity token;
 * the token buys a Supabase session at `/auth/v1/token?grant_type=id_token` under the nonce
 * convention (SHA-256 hex out to Google, raw to the server).
 *
 * The sheet is the whole UI: nothing of ours is drawn until the server has answered.
 * Cancelling is [Failure.Cancelled] and the gate stays silent (01 edge 5).
 *
 * When `BuildConfig.GOOGLE_WEB_CLIENT_ID` is empty there is no native path; [signIn] falls
 * back to Supabase's browser OAuth (PKCE) in a Custom Tab, finished by
 * [SupabaseClient.handleAuthRedirect] from the activity's `nextbody://auth-callback` intent.
 */
object GoogleAuth {
    data class Credential(
        val idToken: String,
        /** The raw nonce; its SHA-256 is what the token carries. */
        val nonce: String,
        /** Google returns the profile name on every sign-in; adopted only when the server has no name yet. */
        val fullName: String?,
    )

    sealed class Failure(message: String) : Exception(message) {
        class Cancelled : Failure("cancelled")
        class NoToken : Failure("no token")
        class NoPresenter : Failure("no presenter")
        /** No web client id configured: only the browser path is available. */
        class NotConfigured : Failure("not configured")
    }

    val hasNativeClient: Boolean get() = BuildConfig.GOOGLE_WEB_CLIENT_ID.isNotBlank()

    /** Native Credential Manager sign-in (port of `GoogleAuth.request()`). */
    suspend fun request(activity: Activity): Credential {
        val clientId = BuildConfig.GOOGLE_WEB_CLIENT_ID
        if (clientId.isBlank()) throw Failure.NotConfigured()
        val raw = Nonce.random()
        val hashed = Nonce.sha256(raw)
        val manager = CredentialManager.create(activity)
        val response = try {
            val option = GetGoogleIdOption.Builder()
                .setServerClientId(clientId)
                .setFilterByAuthorizedAccounts(false)
                .setAutoSelectEnabled(false)
                .setNonce(hashed)
                .build()
            manager.getCredential(activity, GetCredentialRequest.Builder().addCredentialOption(option).build())
        } catch (e: GetCredentialCancellationException) {
            throw Failure.Cancelled()
        } catch (e: NoCredentialException) {
            // No account on the device the bottom sheet can offer: the explicit button flow
            // lets the person add one.
            try {
                val option = GetSignInWithGoogleOption.Builder(clientId).setNonce(hashed).build()
                manager.getCredential(activity, GetCredentialRequest.Builder().addCredentialOption(option).build())
            } catch (e: GetCredentialCancellationException) {
                throw Failure.Cancelled()
            }
        } catch (e: GetCredentialException) {
            throw e
        }
        val credential = response.credential
        if (credential !is CustomCredential ||
            credential.type != GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL) throw Failure.NoToken()
        val google = GoogleIdTokenCredential.createFrom(credential.data)
        if (google.idToken.isEmpty()) throw Failure.NoToken()
        return Credential(google.idToken, raw, google.displayName)
    }

    /**
     * The whole Google door: native token → Supabase session, or (no client id) the browser
     * OAuth fallback, suspended until the redirect has been exchanged. Returns the profile
     * name Google offered, if any.
     */
    suspend fun signIn(activity: Activity): String? {
        if (hasNativeClient) {
            val cred = request(activity)
            SupabaseClient.signInWithGoogle(cred.idToken, cred.nonce)
            return cred.fullName
        }
        val uri: Uri = SupabaseClient.beginOAuth("google")
        CustomTabsIntent.Builder().setShowTitle(true).build().launchUrl(activity, uri)
        SupabaseClient.awaitOAuthRedirect()
        return null
    }

    /**
     * Signing out of Supabase without this leaves the cached Google account selected, and the
     * next tap would sign the same person back in without a picker.
     */
    suspend fun signOut(context: Context) {
        runCatching { CredentialManager.create(context).clearCredentialState(ClearCredentialStateRequest()) }
    }
}
