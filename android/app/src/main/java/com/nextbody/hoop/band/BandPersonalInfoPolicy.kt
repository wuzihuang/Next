package com.nextbody.hoop.band

object BandPersonalInfoPolicy {
    /** VPPeripheralBaseManage: 0 failure, 1 success; unknown replies are not success. */
    fun acknowledged(result: Long): Boolean = result == 1L

    fun owns(expectedAccount: String?, expectedBinding: String?, account: String?, binding: String?, consent: Boolean): Boolean =
        consent && expectedBinding != null && expectedAccount == account && expectedBinding == binding
}
