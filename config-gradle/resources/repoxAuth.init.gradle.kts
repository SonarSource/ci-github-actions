/**
 * Authenticate repox.jfrog.io repositories with Bearer scheme
 * and remove all other Maven repositories (e.g., Maven Central)
 *
 * Credentials can be set by using one of these options:
 * - Gradle property:
 *   - ~/.gradle/gradle.properties:
 *     - {repo name}AuthHeaderValue=...
 *     - {repo name}AuthAccessToken=...
 *     - artifactoryPassword=...
 *   - CLI arg:
 *     - -P{repo name}AuthHeaderValue=...
 *     - -P{repo name}AuthAccessToken=...
 *     - -PartifactoryPassword=...
 *     - -Dorg.gradle.project.{repo name}AuthHeaderValue=...
 *     - -Dorg.gradle.project.{repo name}AuthAccessToken=...
 *     - -Dorg.gradle.project.artifactoryPassword=...
 * - Environment variable:
 *   - ORG_GRADLE_PROJECT_{repo name}AuthHeaderValue=...
 *   - ORG_GRADLE_PROJECT_{repo name}AuthAccessToken=...
 *   - ORG_GRADLE_PROJECT_artifactoryPassword=...
 *   - ARTIFACTORY_ACCESS_TOKEN=...
 *   - ARTIFACTORY_PASSWORD=...
 *   - ARTIFACTORY_PRIVATE_READER_TOKEN=...
 *   - ARTIFACTORY_PRIVATE_PASSWORD=...
 *   - ARTIFACTORY_DEPLOY_PASSWORD=...
 *   - ARTIFACTORY_DEPLOY_ACCESS_TOKEN=...
 *
 * The first one presented will be used.
 */

beforeSettings {
    pluginManagement {
        repositories {
            removeNonRepoxRepositories()
            addRepoxRepositoryIfMissing(providers)
            enableBearerAuthForRepoxRepositories(providers)
        }
        // hook between repository configuration and plugin resolution
        resolutionStrategy {
            eachPlugin {
                repositories {
                    removeNonRepoxRepositories()
                    addRepoxRepositoryIfMissing(providers)
                    enableBearerAuthForRepoxRepositories(providers)
                }
            }
        }
    }
}

settingsEvaluated {
    pluginManagement {
        repositories {
            removeNonRepoxRepositories()
            addRepoxRepositoryIfMissing(providers)
            enableBearerAuthForRepoxRepositories(providers)
        }
    }
    dependencyResolutionManagement {
        repositories {
            removeNonRepoxRepositories()
            addRepoxRepositoryIfMissing(providers)
            enableBearerAuthForRepoxRepositories(providers)
        }
    }
}

allprojects {
    beforeEvaluate {
        repositories {
            removeNonRepoxRepositories()
            addRepoxRepositoryIfMissing(providers)
            enableBearerAuthForRepoxRepositories(providers)
        }
    }
    afterEvaluate {
        repositories {
            removeNonRepoxRepositories()
            addRepoxRepositoryIfMissing(providers)
            enableBearerAuthForRepoxRepositories(providers)
        }
    }
}

class RepoxAuth {
    companion object {
        const val host = "repox.jfrog.io"
        const val authType = "header"
        const val authHeaderName = "Authorization"
        const val authValueScheme = "Bearer"
        val accessTokenEnvVars = listOf(
            "ARTIFACTORY_ACCESS_TOKEN",
            "ARTIFACTORY_DEPLOY_ACCESS_TOKEN",
            "ARTIFACTORY_PASSWORD", // deprecated
            "ARTIFACTORY_PRIVATE_READER_TOKEN", // deprecated
            "ARTIFACTORY_PRIVATE_PASSWORD", // deprecated
            "ARTIFACTORY_DEPLOY_PASSWORD" // deprecated
        )
    }
}

fun RepositoryHandler.addBearerAuthForRepoxRepositories(token: (String) -> Provider<String>) {
    filter {
        (it as? UrlArtifactRepository)?.url?.host == RepoxAuth.host
    }.forEach { repoCandidate ->
        (repoCandidate as? AuthenticationSupported)?.runCatching {
            if (authentication.any { it is HttpHeaderAuthentication }) return@forEach
            apply {
                credentials(HttpHeaderCredentials::class) {
                    name = RepoxAuth.authHeaderName
                    value = token(repoCandidate.name).map {
                        "${RepoxAuth.authValueScheme} ${it.substringAfter(" ")}"
                    }.orNull
                }
            }
        }?.onSuccess {
            it.authentication {
                add(create<HttpHeaderAuthentication>(RepoxAuth.authType))
            }
            logger.info(
                "Set '{}' auth for '{}' repository",
                RepoxAuth.authType,
                repoCandidate.name,
            )
        }
    }
}

fun <T : Any> Provider<T>.orElse(vararg providers: Provider<T>) =
    listOf(this, *providers).reduce { p1, p2 ->
        p1.orElse(p2)
    }

fun RepositoryHandler.removeNonRepoxRepositories() {
    val reposToRemove = filter {
        val urlRepo = it as? UrlArtifactRepository
        // Remove if it's not a URL repository pointing to repox, or if it's mavenLocal() (not a UrlArtifactRepository)
        urlRepo?.url?.host != RepoxAuth.host
    }.toList()

    reposToRemove.forEach { repo ->
        remove(repo)
        val repoType = when {
            repo is UrlArtifactRepository -> "URL (host: ${repo.url.host})"
            else -> "local/file-based (e.g., mavenLocal)"
        }
        logger.info(
            "Removed non-Repox repository '{}' ({})",
            repo.name,
            repoType
        )
    }
}

fun RepositoryHandler.addRepoxRepositoryIfMissing(providers: ProviderFactory) {
    val hasRepoxRepo = any {
        (it as? UrlArtifactRepository)?.url?.host == RepoxAuth.host
    }

    if (!hasRepoxRepo) {
        val baseUrl = System.getenv("ARTIFACTORY_URL")
            ?: providers.gradleProperty("artifactoryUrl").orNull

        if (baseUrl != null) {
            val artifactoryUrl = baseUrl.trimEnd('/') + "/sonarsource"
            maven {
                name = "Repox"
                url = uri(artifactoryUrl)
            }
            logger.info(
                "Added Repox repository at '{}'",
                artifactoryUrl
            )
        } else {
            throw GradleException(
                "No Repox repository found and ARTIFACTORY_URL/artifactoryUrl not set. " +
                    "Please configure ARTIFACTORY_URL environment variable or artifactoryUrl Gradle property."
            )
        }
    }
}

fun RepositoryHandler.enableBearerAuthForRepoxRepositories(providers: ProviderFactory) {
    addBearerAuthForRepoxRepositories {
        providers.gradleProperty("${it}AuthHeaderValue").orElse(
            providers.gradleProperty("${it}AuthAccessToken"),
            providers.gradleProperty("artifactoryPassword"),
            *(RepoxAuth.accessTokenEnvVars.map { envVar ->
                providers.environmentVariable(envVar)
            }.toTypedArray())
        )
    }
}
