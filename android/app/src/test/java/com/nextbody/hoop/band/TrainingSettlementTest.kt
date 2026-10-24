package com.nextbody.hoop.band

import org.junit.Assert.assertEquals
import org.junit.Test

class TrainingSettlementTest {
    @Test fun everyComposedRevisionKeepsItsReadinessExplanation() {
        for ((version, composed) in listOf("target-1.0" to false, "target-1.1" to true, "target-1.2" to true,
            "target-1.3" to true, "target-1.10" to true, "target-2.0" to true, "" to false, "readiness-1.3" to false)) {
            val evidence = mapOf<String, Any?>("target" to mapOf<String, Any?>(
                "version" to version, "target" to 14.6, "lower" to 12.6, "upper" to 16.6, "limited" to false,
                "base_target" to 14.6, "current_reserve" to 67, "reserve_limit" to 14.1))
            assertEquals(version, composed, TrainingSettlement(evidence).target?.hasReserveLimit)
        }
    }
}
