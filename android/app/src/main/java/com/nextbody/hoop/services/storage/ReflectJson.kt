package com.nextbody.hoop.services.storage

import org.json.JSONArray
import org.json.JSONObject
import java.lang.reflect.Field
import java.lang.reflect.GenericArrayType
import java.lang.reflect.Modifier
import java.lang.reflect.ParameterizedType
import java.lang.reflect.Type
import java.lang.reflect.TypeVariable
import java.lang.reflect.WildcardType
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

/**
 * The Swift side persists its caches with `Codable`. Kotlin has no compiler-generated
 * equivalent without a new plugin, so local caches (HomeSnapshot, the outbox items) go
 * through this small reflective codec: plain data classes, enums, sealed hierarchies,
 * `object`s, collections, maps and java.time values round-trip on the same build.
 *
 * It is a *local cache* format only — never sent to the server. Polymorphic values carry
 * `"$t"` (the runtime class name). Decoding failures throw; callers treat that as a miss.
 */
object ReflectJson {
    private const val TYPE = "\$t"
    private const val VALUE = "\$v"
    private val fieldCache = ConcurrentHashMap<Class<*>, List<Field>>()

    fun encode(value: Any?): Any = encode(value, value?.javaClass ?: Any::class.java)

    fun stringify(value: Any?): String = when (val e = encode(value)) {
        is JSONObject -> e.toString()
        is JSONArray -> e.toString()
        else -> JSONArray().put(e).toString()
    }

    inline fun <reified T> parse(text: String): T = decode(text, T::class.java)

    fun <T> decode(text: String, type: Type): T {
        val trimmed = text.trimStart()
        val json: Any = when {
            trimmed.startsWith("{") -> JSONObject(text)
            trimmed.startsWith("[") -> JSONArray(text)
            else -> throw IllegalArgumentException("not JSON")
        }
        @Suppress("UNCHECKED_CAST")
        return decode(json, type) as T
    }

    /** A [JsonCodec] for queue items. */
    fun <T : Any> codec(cls: Class<T>): JsonCodec<T> = object : JsonCodec<T> {
        override fun encode(item: T): JSONObject = ReflectJson.encode(item, cls) as JSONObject
        @Suppress("UNCHECKED_CAST")
        override fun decode(json: JSONObject): T = ReflectJson.decode(json, cls) as T
    }

    private fun rawClass(type: Type): Class<*> = when (type) {
        is Class<*> -> type
        is ParameterizedType -> type.rawType as Class<*>
        is WildcardType -> rawClass(type.upperBounds.firstOrNull() ?: Any::class.java)
        is TypeVariable<*> -> rawClass(type.bounds.firstOrNull() ?: Any::class.java)
        is GenericArrayType -> java.lang.reflect.Array.newInstance(rawClass(type.genericComponentType), 0).javaClass
        else -> Any::class.java
    }

    private fun typeArg(type: Type, index: Int): Type =
        (type as? ParameterizedType)?.actualTypeArguments?.getOrNull(index)?.let {
            if (it is WildcardType) it.upperBounds.firstOrNull() ?: Any::class.java else it
        } ?: Any::class.java

    private fun isLeaf(cls: Class<*>): Boolean =
        cls == String::class.java || cls.isPrimitive || Number::class.java.isAssignableFrom(cls) ||
            cls == java.lang.Boolean::class.java || cls == java.lang.Character::class.java ||
            cls.isEnum || cls == Instant::class.java || cls == LocalDate::class.java ||
            cls == LocalDateTime::class.java || cls == UUID::class.java || cls == Duration::class.java ||
            ZoneId::class.java.isAssignableFrom(cls)

    /** Whether the declared type pins the runtime class exactly (no tag needed). */
    private fun exact(declared: Class<*>, runtime: Class<*>): Boolean {
        if (declared == runtime) return true
        if (declared.isPrimitive) return true
        val boxed = mapOf(
            java.lang.Integer.TYPE to java.lang.Integer::class.java, java.lang.Long.TYPE to java.lang.Long::class.java,
            java.lang.Double.TYPE to java.lang.Double::class.java, java.lang.Float.TYPE to java.lang.Float::class.java,
            java.lang.Boolean.TYPE to java.lang.Boolean::class.java, java.lang.Short.TYPE to java.lang.Short::class.java,
            java.lang.Byte.TYPE to java.lang.Byte::class.java, java.lang.Character.TYPE to java.lang.Character::class.java)
        if (boxed[declared] == runtime) return true
        if (runtime.isEnum && runtime.declaringClass == declared) return true
        if (runtime.superclass?.isEnum == true && runtime.superclass == declared) return true
        return false
    }

    private fun encode(value: Any?, declaredType: Type): Any {
        if (value == null) return JSONObject.NULL
        val declared = rawClass(declaredType)
        val runtime = value.javaClass
        val body = encodeBody(value, declaredType)
        val collectionLike = value is Collection<*> || value is Map<*, *> || value is Array<*>
        if (!collectionLike && !exact(declared, runtime) && !(isLeaf(declared) && declared.isAssignableFrom(runtime) && !declared.isEnum && declared != Any::class.java)) {
            return JSONObject().put(TYPE, (if (runtime.superclass?.isEnum == true) runtime.superclass else runtime).name).put(VALUE, body)
        }
        return body
    }

    private fun encodeBody(value: Any, declaredType: Type): Any = when (value) {
        is String -> value
        is Boolean -> value
        is Int, is Long, is Short, is Byte -> value
        is Double -> if (value.isFinite()) value else value.toString()
        is Float -> if (value.isFinite()) value.toDouble() else value.toString()
        is Char -> value.toString()
        is Enum<*> -> value.name
        is Instant -> value.toString()
        is LocalDate -> value.toString()
        is LocalDateTime -> value.toString()
        is UUID -> value.toString()
        is Duration -> value.toString()
        is ZoneId -> value.id
        is Map<*, *> -> {
            val keyType = typeArg(declaredType, 0)
            val valueType = typeArg(declaredType, 1)
            JSONArray().also { a ->
                value.forEach { (k, v) -> a.put(JSONArray().put(encode(k, keyType)).put(encode(v, valueType))) }
            }
        }
        is Collection<*> -> {
            val element = typeArg(declaredType, 0)
            JSONArray().also { a -> value.forEach { a.put(encode(it, element)) } }
        }
        is Array<*> -> {
            val element = value.javaClass.componentType ?: Any::class.java
            JSONArray().also { a -> value.forEach { a.put(encode(it, element)) } }
        }
        is DoubleArray -> JSONArray().also { a -> value.forEach { a.put(it) } }
        is IntArray -> JSONArray().also { a -> value.forEach { a.put(it) } }
        is LongArray -> JSONArray().also { a -> value.forEach { a.put(it) } }
        is ByteArray -> android.util.Base64.encodeToString(value, android.util.Base64.NO_WRAP)
        else -> {
            val o = JSONObject()
            for (f in fields(value.javaClass)) {
                o.put(f.name, encode(f.get(value), f.genericType))
            }
            o
        }
    }

    private fun fields(cls: Class<*>): List<Field> = fieldCache.getOrPut(cls) {
        val out = mutableListOf<Field>()
        var c: Class<*>? = cls
        while (c != null && c != Any::class.java && c != java.lang.Enum::class.java) {
            for (f in c.declaredFields) {
                val m = f.modifiers
                if (Modifier.isStatic(m) || Modifier.isTransient(m) || f.isSynthetic) continue
                if (f.name.contains("$")) continue
                f.isAccessible = true
                out += f
            }
            c = c.superclass
        }
        out.sortedBy { it.name }
    }

    private val unsafe: Any? by lazy {
        runCatching {
            val c = Class.forName("sun.misc.Unsafe")
            c.getDeclaredField("theUnsafe").apply { isAccessible = true }.get(null)
        }.getOrNull()
    }

    private fun allocate(cls: Class<*>): Any {
        runCatching { cls.getDeclaredField("INSTANCE").takeIf { Modifier.isStatic(it.modifiers) }?.let { it.isAccessible = true; return it.get(null) } }
        runCatching {
            val ctor = cls.getDeclaredConstructor()
            ctor.isAccessible = true
            return ctor.newInstance()
        }
        val u = unsafe ?: throw IllegalStateException("Cannot allocate ${cls.name}")
        return u.javaClass.getMethod("allocateInstance", Class::class.java).invoke(u, cls)!!
    }

    @Suppress("UNCHECKED_CAST")
    private fun decode(json: Any?, declaredType: Type): Any? {
        if (json == null || json == JSONObject.NULL) return null
        var type: Type = declaredType
        var body: Any = json
        if (json is JSONObject && json.has(TYPE) && json.length() == 2 && json.has(VALUE)) {
            type = Class.forName(json.getString(TYPE))
            body = json.get(VALUE)
        }
        val cls = rawClass(type)
        return when {
            cls == String::class.java -> body as String
            cls == java.lang.Boolean.TYPE || cls == java.lang.Boolean::class.java -> body as Boolean
            cls == java.lang.Integer.TYPE || cls == java.lang.Integer::class.java -> (body as Number).toInt()
            cls == java.lang.Long.TYPE || cls == java.lang.Long::class.java -> (body as Number).toLong()
            cls == java.lang.Short.TYPE || cls == java.lang.Short::class.java -> (body as Number).toShort()
            cls == java.lang.Byte.TYPE || cls == java.lang.Byte::class.java -> (body as Number).toByte()
            cls == java.lang.Double.TYPE || cls == java.lang.Double::class.java ->
                if (body is String) body.toDouble() else (body as Number).toDouble()
            cls == java.lang.Float.TYPE || cls == java.lang.Float::class.java ->
                if (body is String) body.toFloat() else (body as Number).toFloat()
            cls == java.lang.Character.TYPE || cls == java.lang.Character::class.java -> (body as String)[0]
            cls.isEnum -> (cls.enumConstants as Array<Enum<*>>).first { it.name == body }
            cls == Instant::class.java -> Instant.parse(body as String)
            cls == LocalDate::class.java -> LocalDate.parse(body as String)
            cls == LocalDateTime::class.java -> LocalDateTime.parse(body as String)
            cls == UUID::class.java -> UUID.fromString(body as String)
            cls == Duration::class.java -> Duration.parse(body as String)
            ZoneId::class.java.isAssignableFrom(cls) -> ZoneId.of(body as String)
            cls == ByteArray::class.java -> android.util.Base64.decode(body as String, android.util.Base64.NO_WRAP)
            cls == DoubleArray::class.java -> (body as JSONArray).let { a -> DoubleArray(a.length()) { a.getDouble(it) } }
            cls == IntArray::class.java -> (body as JSONArray).let { a -> IntArray(a.length()) { a.getInt(it) } }
            cls == LongArray::class.java -> (body as JSONArray).let { a -> LongArray(a.length()) { a.getLong(it) } }
            Map::class.java.isAssignableFrom(cls) -> {
                val a = body as JSONArray
                val out = LinkedHashMap<Any?, Any?>()
                for (i in 0 until a.length()) {
                    val pair = a.getJSONArray(i)
                    out[decode(pair.opt(0), typeArg(type, 0))] = decode(pair.opt(1), typeArg(type, 1))
                }
                if (cls.isInterface || Modifier.isAbstract(cls.modifiers) || cls == LinkedHashMap::class.java || cls == HashMap::class.java) out
                else (allocate(cls) as MutableMap<Any?, Any?>).also { it.putAll(out) }
            }
            Set::class.java.isAssignableFrom(cls) -> {
                val a = body as JSONArray
                val el = typeArg(type, 0)
                (0 until a.length()).mapTo(LinkedHashSet()) { decode(a.opt(it), el) }
            }
            Collection::class.java.isAssignableFrom(cls) || cls == Iterable::class.java -> {
                val a = body as JSONArray
                val el = typeArg(type, 0)
                (0 until a.length()).mapTo(ArrayList()) { decode(a.opt(it), el) }
            }
            cls.isArray -> {
                val a = body as JSONArray
                val el = cls.componentType!!
                val arr = java.lang.reflect.Array.newInstance(el, a.length())
                for (i in 0 until a.length()) java.lang.reflect.Array.set(arr, i, decode(a.opt(i), el))
                arr
            }
            else -> {
                val o = body as JSONObject
                val instance = allocate(cls)
                if (cls.declaredFields.any { it.name == "INSTANCE" && Modifier.isStatic(it.modifiers) }) return instance
                for (f in fields(cls)) {
                    if (!o.has(f.name)) continue
                    val v = decode(o.opt(f.name), f.genericType)
                    if (v == null && f.type.isPrimitive) continue
                    f.set(instance, v)
                }
                instance
            }
        }
    }
}
