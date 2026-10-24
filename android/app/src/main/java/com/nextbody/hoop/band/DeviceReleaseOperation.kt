package com.nextbody.hoop.band

import com.nextbody.hoop.services.SupabaseFailure

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import java.net.SocketTimeoutException
import java.io.IOException

/** The account acknowledgment completes removal. Radio cleanup may still be draining
 *  an SDK command, so it must never hold that acknowledgment on screen. */
object DeviceReleaseOperation {
    suspend fun <Response> run(
        request: suspend () -> Response,
        publish: (Response) -> Unit,
        cleanup: suspend () -> Unit,
        taskScope: CoroutineScope = BandMain.scope,
    ): Job {
        val response = request()
        publish(response)
        return taskScope.launch { cleanup() }
    }
}

sealed class DeviceReleaseError : Exception() {
    data object Busy : DeviceReleaseError() { private fun readResolve(): Any = Busy }
    data object PendingChanges : DeviceReleaseError() { private fun readResolve(): Any = PendingChanges }
    data object BindingUnavailable : DeviceReleaseError() { private fun readResolve(): Any = BindingUnavailable }

    companion object {
        /** Swift `.busy` / `.pendingChanges` / `.bindingUnavailable`. */
        fun busy(): DeviceReleaseError = Busy
        fun pendingChanges(): DeviceReleaseError = PendingChanges
        fun bindingUnavailable(): DeviceReleaseError = BindingUnavailable

        fun message(error: Throwable): String {
            when (error) {
                is Busy -> return "The NEXTBODY is switching or finishing a command. Try again shortly."
                is PendingChanges -> return "Your last wear change is still being saved. Try again shortly."
                is BindingUnavailable -> return "The pairing details are not loaded yet. Reopen Device and try again."
                else -> {}
            }
            if (error is SupabaseFailure.Http) {
                if (error.code == 404 || error.body.contains("PGRST202")) {
                    return "NEXTBODY removal is temporarily unavailable. Please try again later."
                }
                if (error.code == 401) return "Your session has expired. Sign in again to remove this NEXTBODY."
                if (error.code == 403) return "The pairing has changed. Reopen Device to refresh it."
            }
            val underlying = if (error is SupabaseFailure.Transport) error.error else error
            // Swift URLError → Java/OkHttp IO exceptions.
            if (underlying is IOException) {
                if (underlying is SocketTimeoutException || underlying is java.io.InterruptedIOException) {
                    return "Removal could not be confirmed in time. Retry to check; your history is safe."
                }
                return "Unable to reach the server. Check your internet connection and try again."
            }
            return "Removal could not be confirmed. Retry to check; your history is safe."
        }
    }
}
