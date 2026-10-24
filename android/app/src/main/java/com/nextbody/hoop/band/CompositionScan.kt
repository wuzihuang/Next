package com.nextbody.hoop.band

import java.time.Instant
import java.util.UUID

// From Services/Band/CompositionWindowMath.swift — only the row type `DataStore` holds.
// CompositionWindowMath itself is ported by its owner; it must not redeclare this type.

/**
 * One `body_composition` row the page is allowed to draw. Only fields that actually
 * land in Postgres — SDK extras that never left RAM are not here.
 */
data class CompositionScan(
    var id: UUID,
    var at: Instant,
    var bodyFatPercent: Double?,
    var fatMassKg: Double?,
    var leanMassKg: Double?,
    var bmrKcal: Double?,
    var inputWeightKg: Double?,
    var muscleMassKg: Double? = null,
    var bodyWaterPercent: Double? = null,
    var boneMassKg: Double? = null,
    var proteinPercent: Double? = null,
)
