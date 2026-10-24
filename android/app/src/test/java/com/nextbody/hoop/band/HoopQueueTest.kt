package com.nextbody.hoop.band

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Collections

class HoopQueueTest {
    @Test
    fun higherPriorityJumpsAheadButNeverInterruptsInFlight() = runBlocking {
        val queue = HoopQueue()
        val order = Collections.synchronizedList(mutableListOf<String>())
        val gate = CompletableDeferred<Unit>()
        val started = CompletableDeferred<Unit>()
        queue.enqueue("first", HoopQueue.Priority.p2) { started.complete(Unit); gate.await(); order.add("first") }
        started.await()
        queue.enqueue("bg1", HoopQueue.Priority.p2) { order.add("bg1") }
        queue.enqueue("page", HoopQueue.Priority.p1) { order.add("page") }
        queue.enqueue("tap", HoopQueue.Priority.p0) { order.add("tap") }
        queue.enqueue("bg2", HoopQueue.Priority.p2) { order.add("bg2") }
        assertEquals("first", queue.current)
        assertEquals(5, queue.depth)
        gate.complete(Unit)
        val last = withTimeout(5_000) { queue.run("tail", HoopQueue.Priority.p2) { order.add("tail"); 42 } }
        assertEquals(42, last)
        assertEquals(listOf("first", "tap", "page", "bg1", "bg2", "tail"), order.toList())
    }

    @Test
    fun aFailedJobDoesNotStopTheQueueAndRunRethrows() = runBlocking {
        val queue = HoopQueue()
        var threw = false
        try {
            queue.run<Int>("boom") { throw BandError.Busy }
        } catch (e: BandError) { threw = e == BandError.Busy }
        assertTrue(threw)
        assertEquals("ok", withTimeout(5_000) { queue.run("next") { "ok" } })
    }

    @Test
    fun cancelPendingLeavesTheInFlightJobAlone() = runBlocking {
        val queue = HoopQueue()
        val gate = CompletableDeferred<Unit>()
        val started = CompletableDeferred<Unit>()
        val ran = Collections.synchronizedList(mutableListOf<String>())
        queue.enqueue("inflight") { started.complete(Unit); gate.await(); ran.add("inflight") }
        started.await()
        queue.enqueue("dropped") { ran.add("dropped") }
        queue.cancelPending()
        gate.complete(Unit)
        withTimeout(5_000) { queue.run("after") { ran.add("after") } }
        assertEquals(listOf("inflight", "after"), ran.toList())
    }
}
