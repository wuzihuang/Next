package com.nextbody.hoop.band

import com.nextbody.hoop.services.RequestSession
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Job
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.isActive
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean

/** One phone call owns its confirmation, eligibility and completion. Both the app and
 *  controlled adapters execute through this interface; every suspended step rechecks the
 *  same account/session, turn and band before it can issue a subsequent action.
 *  Main-thread only (Swift `@MainActor`). The AI caller (PhoneToolRunner) is not ported:
 *  AI is disabled on Android; UI only reads [Prompt] / [Execution]. */
class PhoneToolExecution(
    private val current: () -> Environment,
    private val sleep: suspend (Double) -> Unit,
    private val changed: (Prompt?, String?) -> Unit,
) {
    internal class Cancellation {
        private val cancelled = AtomicBoolean(false)
        fun cancel() = cancelled.set(true)
        val isCancelled: Boolean get() = cancelled.get()
    }

    data class Scope(val session: RequestSession, val turnID: UUID, val binding: String?)

    data class Environment(val scope: Scope, val consent: Boolean, val foreground: Boolean)

    data class Prompt(
        val id: UUID,
        val title: String,
        val detail: String,
        /** A confirm whose own fields the tap may correct before it approves. The model
         *  proposes by ear — #28's night is the clearest case — and the person who lived
         *  the thing being written is already looking at the screen. */
        val edit: Edit? = null,
    ) {
        sealed class Edit {
            /** The night's two clock times, `HH:MM`, as proposed. Approved values come back
             *  as the `start` and `end` the tool writes. */
            data class SleepWindow(val start: String, val end: String) : Edit()
        }
    }

    class Failure private constructor(val raw: String) : Exception(raw) {
        override fun equals(other: Any?): Boolean = other is Failure && other.raw == raw
        override fun hashCode(): Int = raw.hashCode()

        companion object {
            val cancelled = Failure("CANCELLED")
            val background = Failure("APP_BACKGROUND")
            val consentRequired = Failure("CONSENT_REQUIRED")
            val sessionChanged = Failure("SESSION_CHANGED")
            val bindingChanged = Failure("BAND_DISCONNECTED")
            val alarmSlotsFull = Failure("ALARM_SLOTS_FULL")
            val alarmNotFound = Failure("ALARM_NOT_FOUND")
            val alreadyExecuted = Failure("CALL_ALREADY_EXECUTED")
        }
    }

    class Execution internal constructor(
        val scope: Scope,
        val callID: String,
        private val cancellation: Cancellation,
        private val current: () -> Environment,
    ) {
        val id: UUID = UUID.randomUUID()
        internal var failure: Failure? = null
        internal var finished = false
        /** What the confirm's own fields were set to before the tap approved it. A tool
         *  reads these over its arguments: an edited confirm writes what the screen said,
         *  not what the model guessed. */
        var edited: Map<String, String> = emptyMap()
            internal set

        /** Check immediately before each side effect. A read followed by a write must use
         *  separate steps so the read's suspension cannot carry old authority to the write. */
        fun check() {
            failure?.let { throw it }
            val now = current()
            val reason: Failure? = when {
                cancellation.isCancelled || finished -> Failure.cancelled
                !now.foreground -> Failure.background
                !now.consent -> Failure.consentRequired
                scope.session.owner == null || now.scope.session != scope.session -> Failure.sessionChanged
                now.scope.turnID != scope.turnID -> Failure.cancelled
                now.scope.binding != scope.binding -> Failure.bindingChanged
                else -> null
            }
            if (reason != null) { failure = reason; throw reason }
        }

        val isAuthorized: Boolean get() = runCatching { check() }.isSuccess

        suspend fun <Value> perform(action: suspend () -> Value): Value {
            if (!currentCoroutineContext().isActive) cancellation.cancel()
            check()
            val result = action()
            if (!currentCoroutineContext().isActive) cancellation.cancel()
            check()
            return result
        }

        suspend fun setAlarm(
            draft: BandAlarm,
            read: suspend () -> List<BandAlarm>,
            write: suspend (BandAlarm) -> List<BandAlarm>,
        ): Pair<Int, List<BandAlarm>> {
            val alarms = perform(read)
            val id = BandAlarmMath.nextID(alarms) ?: throw Failure.alarmSlotsFull
            val next = draft.copy(id = id)
            val after = perform { write(BandAlarmMath.prepared(next)) }
            return id to after
        }

        suspend fun deleteAlarm(
            id: Int,
            read: suspend () -> List<BandAlarm>,
            delete: suspend (BandAlarm) -> List<BandAlarm>,
        ): List<BandAlarm> {
            val alarms = perform(read)
            val alarm = alarms.firstOrNull { it.id == id } ?: throw Failure.alarmNotFound
            return perform { delete(alarm) }
        }
    }

    data class Confirmation(val title: String, val detail: String, val edit: Prompt.Edit?)

    private class Pending(val execution: Execution, val continuation: CompletableDeferred<Boolean>, val timer: Job)

    private val executions = LinkedHashMap<UUID, Execution>()
    private var pending: Pending? = null
    private var prompt: Prompt? = null
    private var displayed: Pair<UUID, String>? = null
    private var admittedScope: Scope? = null
    private val admittedCalls = mutableSetOf<String>()

    suspend fun <Value> run(
        scope: Scope, callID: String, name: String,
        confirmation: Confirmation?,
        action: suspend (Execution) -> Value,
    ): Value {
        val cancellation = Cancellation()
        val execution = Execution(scope, callID, cancellation, current)
        execution.check()
        if (admittedScope != scope) { admittedScope = scope; admittedCalls.clear() }
        if (!admittedCalls.add(callID)) throw Failure.alreadyExecuted
        // A new call replaces the visible confirmation; the displaced waiter is completed
        // before installing its successor, and its timer can only resolve its own UUID.
        invalidateAll(Failure.cancelled)
        executions[execution.id] = execution
        displayed = execution.id to name
        emit()
        try {
            execution.check()
            if (confirmation != null) {
                val approved = waitForConfirmation(execution, confirmation.title, confirmation.detail, confirmation.edit)
                execution.check()
                if (!approved) throw Failure.cancelled
            }
            return execution.perform { action(execution) }
        } catch (e: CancellationException) {
            cancellation.cancel()
            invalidate(execution, Failure.cancelled)
            throw e
        } finally {
            execution.finished = true
            executions.remove(execution.id)
            if (displayed?.first == execution.id) displayed = null
            emit()
        }
    }

    /** `edited` is what the confirm's own fields read at the moment of the tap. It is kept
     *  only on an approval that is still eligible: a cancelled or expired confirm writes
     *  nothing, so there is nothing for it to carry. */
    fun resolve(id: UUID, approved: Boolean, edited: Map<String, String> = emptyMap()) {
        val waiting = pending ?: return
        if (waiting.execution.id != id) return
        pending = null
        prompt = null
        waiting.timer.cancel()
        val eligible = runCatching { waiting.execution.check() }.isSuccess
        if (approved && eligible) waiting.execution.edited = edited
        waiting.continuation.complete(approved && eligible)
        emit()
    }

    /** Host events wake confirmation immediately; checks at every action remain the
     *  authority even if a notification has not yet reached the main thread. */
    fun refreshEligibility() {
        for (execution in executions.values.toList()) {
            try { execution.check() }
            catch (reason: Failure) { invalidate(execution, reason) }
            catch (_: Throwable) { invalidate(execution, Failure.cancelled) }
        }
    }

    fun invalidateAll(reason: Failure) {
        for (execution in executions.values.toList()) invalidate(execution, reason)
    }

    private fun invalidate(execution: Execution, reason: Failure) {
        execution.failure = execution.failure ?: reason
        resolve(execution.id, approved = false)
    }

    private suspend fun waitForConfirmation(execution: Execution, title: String, detail: String, edit: Prompt.Edit?): Boolean {
        val continuation = CompletableDeferred<Boolean>()
        val timer = BandMain.launch {
            try { sleep(60.0) } catch (_: Throwable) { return@launch }
            resolve(execution.id, approved = false)
        }
        pending = Pending(execution, continuation, timer)
        prompt = Prompt(id = execution.id, title = title, detail = detail, edit = edit)
        emit()
        return continuation.await()
    }

    private fun emit() = changed(prompt, displayed?.second)
}
