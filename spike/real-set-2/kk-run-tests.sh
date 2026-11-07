#!/bin/sh
# kurtkode's test suite as the eval checks it: serially (in parallel, timing tests fail at random under the sandbox's
# load), without the tests the sandbox breaks (they start a sandbox of their own, open local sockets, or signal
# process groups), and with SwiftPM's own sandbox off (macOS refuses a sandbox inside another).
export KURTKODE_NO_KEYCHAIN=1
cd AgentCore && exec swift test --disable-sandbox --no-parallel --skip 'aCommandsChangeRewindsThroughTheCLISession|aFailureTheSandboxDidntCauseGetsNoNote|aRunAtTheStepLimitEarnsAnOfferAndYesSwitchesTheModel|explainsAuthAndExpiredSessions|gitHooksAndConfigStayReadOnly|goodAndBadRateTheLastReply|hearsTheServersOwnStream|killStopsTheGroupAndAQuickFailureIsReported|networkIsOffUnlessAllowed|planModeRunsReadOnlyCommandsOnly|r5_12_planCommandsCantReadWithheldFiles|talksStreamableHTTP|theHubSendsTheKeychainTokenOnlyWithoutItsOwnHeader|theOffersReviewRunsOnTheOffersModel|thePlanSandboxBlocksWritesInTheProject|timeoutKillsTheWholeProcessGroup|writableFoldersAreWritableInTheSandboxButTheirGitHooksArent|writesInsideTheProjectWork|writesOutsideAreBlockedAndReported' "$@"
