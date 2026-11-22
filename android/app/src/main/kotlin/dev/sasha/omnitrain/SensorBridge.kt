package dev.sasha.omnitrain

/**
 * What `MainActivity` needs from the device sensors of its flavor (plan 298,
 * D-29801): the answer to a runtime-permission prompt it relayed. The phone
 * flavor has no sensors and registers none.
 */
interface SensorBridge {
    /** Returns true when the result belonged to this bridge and was handled. */
    fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean
}
