package sh.reception.flutter

/** Validates the FCM registration token that Dart passes, with the SDK's rule. */
internal object PushToken {
    private val pattern = Regex("^[A-Za-z0-9_:-]{1,4096}$")

    fun isValid(token: String): Boolean = pattern.matches(token)
}
