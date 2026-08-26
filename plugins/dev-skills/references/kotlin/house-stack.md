# House JVM Stack

This is the author's default JVM stack. It covers dependency injection,
testing, HTTP, CLI, Kubernetes, and the Gradle build.

Load this file only when the project already uses these libraries. Read the
build file first. If the project uses a different library for the same job,
match the project. Never add one of these dependencies to a repository that
does not already declare it.

The project's own conventions always win. Where this file and the project
disagree, follow the project.

Stack summary:

- **DI**: Koin
- **Testing**: JUnit 5, TestContainers, AssertJ
- **CLI**: Picocli
- **HTTP**: Ktor (client and server)
- **Kubernetes**: Fabric8 client
- **Build**: Gradle with Kotlin DSL and version catalogs
- **Fat JAR**: `com.gradleup.shadow`
- **Coverage**: Kover

---

## Koin Conventions

- Define modules in `src/main/kotlin/.../di/` directories
- Always bind to an interface: `single<MyInterface> { MyImpl() }` not `single { MyImpl() }`
- Use `factory {}` for objects that should not be singletons
- Never use `KoinComponent` in domain classes — inject via constructor only
- Test setup:
  ```kotlin
  @BeforeEach
  fun setUp() {
      startKoin { modules(testModule) }
  }

  @AfterEach
  fun tearDown() {
      stopKoin()
  }
  ```

---

## TestContainers Conventions

Use TestContainers for any test touching a real database, Kafka, Redis, or other infrastructure:

```kotlin
@Testcontainers
class MyIntegrationTest {
    companion object {
        @Container
        @JvmStatic
        val postgres = PostgreSQLContainer<Nothing>("postgres:16")
    }
}
```

Never mock infrastructure in integration tests — use real containers.

---

## AssertJ Conventions

Always use AssertJ. Never use JUnit `assertEquals`, `assertNull`, `assertTrue`:

```kotlin
// Collections
assertThat(list).containsExactly(a, b, c)
assertThat(list).hasSize(3)
assertThat(list).isEmpty()

// Strings
assertThat(str).isEqualTo("expected")
assertThat(str).contains("substring")
assertThat(str).startsWith("prefix")

// Exceptions
assertThatThrownBy { service.call() }
    .isInstanceOf(IllegalArgumentException::class.java)
    .hasMessageContaining("expected message")

// Objects
assertThat(obj).isNotNull()
assertThat(obj).isEqualTo(expected)
```

---

## Ktor Conventions

```kotlin
// Server
embeddedServer(Netty, port = 8080) {
    install(ContentNegotiation) { json() }
    routing {
        get("/health") { call.respond(mapOf("status" to "ok")) }
    }
}.start(wait = true)

// Client
val client = HttpClient(CIO) {
    install(ContentNegotiation) { json() }
    install(HttpTimeout) { requestTimeoutMillis = 5000 }
}

// Test
@Test
fun `GET health returns 200`() = testApplication {
    val response = client.get("/health")
    assertThat(response.status).isEqualTo(HttpStatusCode.OK)
}
```

---

## Picocli Conventions

```kotlin
@Command(
    name = "my-tool",
    description = ["Does the thing"],
    mixinStandardHelpOptions = true
)
class MyCommand : Runnable {
    @Option(names = ["-n", "--name"], description = ["Name to process"])
    var name: String = ""

    override fun run() {
        // Delegate to service — keep commands thin
        MyService().process(name)
    }
}

fun main(args: Array<String>) {
    exitProcess(CommandLine(MyCommand()).execute(*args))
}
```

---

## Fabric8 Conventions

```kotlin
// Always inject as singleton and close via lifecycle
single<KubernetesClient> { KubernetesClientBuilder().build() }

// Use typed resources — not generic API
client.apps().deployments().inNamespace("default").list()
client.pods().inNamespace(ns).withLabel("app", name).list()

// Always use use{} or manage lifecycle explicitly
client.use { c ->
    c.pods().inNamespace("default").list()
}
```

For integration tests, use a k3s or kind TestContainer.

---

## Version Catalog Management

The version catalog lives at `gradle/libs.versions.toml`:

```toml
[versions]
ktor = "2.3.12"
koin = "3.5.6"
shadow = "8.3.0"

[libraries]
ktor-client-core = { module = "io.ktor:ktor-client-core", version.ref = "ktor" }
koin-core = { module = "io.insert-koin:koin-core", version.ref = "koin" }

[plugins]
shadow = { id = "com.gradleup.shadow", version.ref = "shadow" }
```

To add or update a dependency:
1. Read the current catalog
2. Show the proposed change as a diff
3. Get user confirmation before writing
4. After updating: `./gradlew dependencies --configuration runtimeClasspath 2>&1 | tail -30`

---

## Shadow JAR

Use `com.gradleup.shadow` — **not** `com.github.johnrengelman.shadow`:

```kotlin
// build.gradle.kts
plugins {
    id("com.gradleup.shadow") version libs.versions.shadow.get()
}

tasks.shadowJar {
    archiveClassifier.set("")
    mergeServiceFiles()
    manifest {
        attributes["Main-Class"] = "com.example.MainKt"
    }
}
```

Build and verify:
```bash
./gradlew shadowJar 2>&1
ls -lh build/libs/*.jar
java -jar build/libs/myapp.jar --help
```

---

## Kover Coverage

If Kover is configured:

```bash
# Generate the XML coverage report
./gradlew koverXmlReport 2>&1

# Extract overall line coverage
grep -o 'missed="[0-9]*" covered="[0-9]*"' build/reports/kover/xml/report.xml | \
  awk -F'"' '{m+=$2; c+=$4} END {printf "Line coverage: %.1f%%\n", (c/(m+c))*100}'
```

If coverage drops below 80%, flag it as a Warning in your report.
