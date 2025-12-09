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
    logger.debug("Applying Repox configuration init script before settings evaluation")
    pluginManagement {
        repositories {
            configureRepoxRepositories(providers)
        }
        // hook between repository configuration and plugin resolution
        resolutionStrategy {
            eachPlugin {
                repositories {
                    configureRepoxRepositories(providers)
                }
            }
        }
    }
    dependencyResolutionManagement {
        repositories {
            configureRepoxRepositories(providers)
        }
    }
}

settingsEvaluated {
    logger.debug("Applying Repox configuration init script after settings evaluation")
    pluginManagement {
        repositories {
            configureRepoxRepositories(providers)
        }
    }
    dependencyResolutionManagement {
        repositories {
            configureRepoxRepositories(providers)
        }
    }
}

allprojects {
    beforeEvaluate {
        logger.debug("Applying Repox configuration init script before project '${project.name}' evaluation")
        repositories {
            configureRepoxRepositories(providers)
        }
    }
    afterEvaluate {
        logger.debug("Applying Repox configuration init script after project '${project.name}' evaluation")
        repositories {
            configureRepoxRepositories(providers)
        }
    }
}

class RepoxAuth {
    companion object {
        const val host = "repox.jfrog.io"
        val artifactoryUrl = System.getenv("ARTIFACTORY_URL") ?: "https://repox.jfrog.io/artifactory"
        val sonarsourceRepositoryUrl =
            RepoxAuth.artifactoryUrl.trimEnd('/') + "/" + (System.getenv("SONARSOURCE_REPOSITORY") ?: "sonarsource")
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
            logger.debug("Set '{}' auth for '{}' repository", RepoxAuth.authType, repoCandidate.name)
        }
    }
}

fun <T : Any> Provider<T>.orElse(vararg providers: Provider<T>) =
    listOf(this, *providers).reduce { p1, p2 ->
        p1.orElse(p2)
    }

fun RepositoryHandler.configureRepoxRepositories(providers: ProviderFactory) {
    addRepoxRepositoryIfMissing()
    removeNonRepoxRepositories()
    enableBearerAuthForRepoxRepositories(providers)
}

fun RepositoryHandler.removeNonRepoxRepositories() {
    val reposToProcess = toList()
    reposToProcess.forEach { repo ->
        val urlRepo = repo as? UrlArtifactRepository
        val repoUrl = urlRepo?.url?.toString()?.trimEnd('/')
        val isSonarSourceRepo = repoUrl == RepoxAuth.sonarsourceRepositoryUrl
        if (!isSonarSourceRepo) {
            val repoInfo = repoUrl ?: "class: ${repo.javaClass.simpleName}"
            val isLocal = urlRepo?.url?.let { it.scheme == "file" } ?: true
            val isRepoxRepo = urlRepo?.url?.host == RepoxAuth.host
            if (!isLocal && !isRepoxRepo) {
                remove(repo)
                logger.warn("Removed '{}' repository: {}", repo.name, repoInfo)
            } else {
                logger.info("Kept '{}' repository: {}", repo.name, repoInfo)
            }
        }
    }
}

fun RepositoryHandler.addRepoxRepositoryIfMissing() {
    val hasRepoxRepo = any {
        (it as? UrlArtifactRepository)?.url?.host == RepoxAuth.host
    }
    if (!hasRepoxRepo) {
        maven {
            name = "Repox"
            url = uri(RepoxAuth.sonarsourceRepositoryUrl)
        }
        logger.info("Added 'Repox' repository: '{}'", RepoxAuth.sonarsourceRepositoryUrl)
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
