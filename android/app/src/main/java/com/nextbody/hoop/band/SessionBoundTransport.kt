package com.nextbody.hoop.band

import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.isActive
import com.nextbody.hoop.services.RequestSession
import okhttp3.Request
import java.util.UUID
import kotlin.coroutines.cancellation.CancellationException

/** A refresh may change credentials, never the account/session that owns the request body.
 *  `send` returns the body and the HTTP status code (Swift: `(Body, URLResponse)`). */
object SessionBoundTransport {
    fun identifying(request: Request, requestID: UUID): Request =
        request.newBuilder().header("Idempotency-Key", requestID.toString().lowercase()).build()

    suspend fun <Body> perform(
        request: Request,
        session: RequestSession,
        current: suspend () -> RequestSession,
        send: suspend (Request) -> Pair<Body, Int>,
        refresh: suspend () -> String?,
    ): Pair<Body, Int> {
        suspend fun guard() {
            if (!currentCoroutineContext().isActive || current() != session) throw CancellationException()
        }
        guard()
        val first = send(request)
        guard()
        if (first.second != 401) return first
        val token = refresh() ?: return first
        guard()
        val retry = request.newBuilder().header("Authorization", "Bearer $token").build()
        val result = send(retry)
        guard()
        return result
    }
}
