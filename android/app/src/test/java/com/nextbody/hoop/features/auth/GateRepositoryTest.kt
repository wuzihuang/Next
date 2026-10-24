package com.nextbody.hoop.features.auth

import com.nextbody.hoop.band.Band
import com.nextbody.hoop.data.Profile
import com.nextbody.hoop.model.Goal
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.time.Instant

@OptIn(ExperimentalCoroutinesApi::class)
class GateRepositoryTest {
    private val seeded = Band.allowsSeed

    @Before fun setUp() {
        Dispatchers.setMain(UnconfinedTestDispatcher())
    }

    @After fun tearDown() {
        Band.allowsSeed = seeded
        Dispatchers.resetMain()
    }

    @Test fun onboardingProfileSaveReachesTheServicesRepository() = runTest {
        Band.allowsSeed = true
        val profile = Profile(name = "", email = "", birthdate = Instant.EPOCH, heightCm = 170.0,
            sexIsMale = true, goal = Goal.cut, usesMetric = true, appleHealthLinked = false)
        assertTrue(GateRepository.saveProfile(profile, listOf("sex")))
    }

    @Test fun signInNameSaveReachesTheServicesRepository() = runTest {
        GateRepository.saveDisplayName("Ada")
    }
}
