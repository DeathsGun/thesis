# scan_analysis.R
# Parses all.ndjson from the script scanner and builds the tables needed
# for portability, package usage and feature usage analysis.
#
# Put all.ndjson in the same folder as this script, or change the path below.

library(jsonlite)
library(dplyr)
library(tidyr)
library(ggplot2)
library(patchwork)  # install.packages("patchwork") if not already installed

# ---- 0. Shared plot styling -------------------------------------------------
# Default ggplot styling reads fine on screen and gets muddy once pasted into
# a thesis document. This is a plain, high-contrast theme meant for print.

thesis_theme <- function() {
  theme_minimal(base_size = 13) +
    theme(
      panel.grid.minor = element_blank(),
      panel.grid.major.y = element_blank(),
      plot.title = element_text(face = "bold", size = 14),
      axis.title = element_text(size = 12),
      axis.text = element_text(size = 11, colour = "black")
    )
}

# saves at a fixed size/resolution so labels stay legible when embedded in
# a document, regardless of how big the plot pane happened to be on screen
save_plot <- function(plot, filename, width = 8, height = 5) {
  ggsave(filename, plot, width = width, height = height, dpi = 300)
}

# One color meaning, reused on every chart that touches the V8 question, so
# a reader can pattern-match red/blue across the whole section instead of
# re-reading a legend each time. "shimmable" gets its own color rather than
# being folded into "viable", since it is a real caveat, not a green light.
VIABILITY_COLORS <- c(
  "V8 viable"           = "steelblue",
  "shimmable (mostly)"  = "#e69f00",
  "hard floor"          = "firebrick",
  "unresolved"          = "grey60"
)

# ---- 1. Load ---------------------------------------------------------------

raw <- stream_in(file("all.ndjson"))

# ---- 2. Split by record type -----------------------------------------------

scripts <- raw %>%
  filter(type == "script") %>%
  select(tenantId, scriptId, versionId, contentHash, bytes)

contents <- raw %>%
  filter(type == "content") %>%
  select(contentHash, lines, likelyMinified, parsed, pluginSet,
         importCount, dynamicCount, usesPackages, usesNodeBuiltins,
         usesNodeGlobals, usesDynamicCode, selfContained, runtimeFeatures)

imports <- raw %>%
  filter(type == "import") %>%
  select(contentHash, package, specifier, category, kind, resolution, count)

dynamic_calls <- raw %>%
  filter(type == "dynamic")

parse_errors <- raw %>%
  filter(type == "error") %>%
  select(contentHash)

skipped <- raw %>%
  filter(type == "skipped") %>%
  select(tenantId, scriptId, versionId)

# ---- 2.5. Optional: drop minified/bundled scripts ---------------------------
# A script that inlines a bundled library shows no import for it, since the
# scan only sees what the script itself requires. Those cases are flagged
# likelyMinified on the content row. That means a minified script's
# self-contained or packages-only label is less trustworthy than for
# ordinary code, since it may be hiding a whole dependency tree. Set
# DROP_MINIFIED to FALSE to keep them in and see the effect side by side.

DROP_MINIFIED <- TRUE

minified_hashes <- contents %>%
  filter(likelyMinified) %>%
  pull(contentHash)

affected_versions <- scripts %>% filter(contentHash %in% minified_hashes) %>% nrow()
affected_tenants  <- scripts %>% filter(contentHash %in% minified_hashes) %>%
  distinct(tenantId) %>% nrow()

cat(sprintf(
  "likelyMinified: %d / %d contents, %d script versions, %d tenants affected\n",
  length(minified_hashes), nrow(contents), affected_versions, affected_tenants))

if (DROP_MINIFIED) {
  contents <- contents %>% filter(!contentHash %in% minified_hashes)
  scripts  <- scripts  %>% filter(!contentHash %in% minified_hashes)
  imports  <- imports  %>% filter(!contentHash %in% minified_hashes)
  cat("DROP_MINIFIED is TRUE: these are excluded from every table below.\n")
} else {
  cat("DROP_MINIFIED is FALSE: minified content stays in, treat its\n",
      "self-contained/packages-only labels with caution.\n")
}

# ---- 3. Portability bucket per content -------------------------------------
# Mirrors the hierarchy used in portability.csv: hardest constraint wins.
# Verified against the published totals: node-globals must take precedence
# over node-builtins for the overlap case, not the other way round, or the
# 1420/177 split in the writeup does not reproduce.
# Parse failures still have a "content" row (parsed = FALSE, all usesX flags
# NA), which case_when's final TRUE clause catches and labels "unknown".

content_bucket <- contents %>%
  mutate(bucket = case_when(
    usesDynamicCode  ~ "dynamic-code",
    usesNodeGlobals  ~ "node-globals",
    usesNodeBuiltins ~ "node-builtins",
    usesPackages     ~ "packages-only",
    selfContained    ~ "self-contained",
    TRUE ~ "unknown"
  )) %>%
  select(contentHash, bucket)

scripts_bucketed <- scripts %>%
  left_join(content_bucket, by = "contentHash") %>%
  mutate(bucket = if_else(is.na(bucket), "unknown", bucket))

# counts matching portability.csv's three columns
portability_contents <- content_bucket %>% count(bucket, name = "contents")
portability_versions <- scripts_bucketed %>% count(bucket, name = "versions")
portability_tenants  <- scripts_bucketed %>%
  distinct(tenantId, bucket) %>%
  count(bucket, name = "tenants")

portability_summary <- portability_contents %>%
  left_join(portability_versions, by = "bucket") %>%
  left_join(portability_tenants, by = "bucket") %>%
  arrange(desc(contents))

print(portability_summary)

# ---- 4. Packages by tenant --------------------------------------------------

package_tenants <- imports %>%
  left_join(scripts %>% select(tenantId, contentHash), by = "contentHash",
            relationship = "many-to-many") %>%
  distinct(tenantId, package) %>%
  count(package, name = "tenants") %>%
  arrange(desc(tenants))

# ---- 5. Runtime feature usage (Node globals, not commonjs bookkeeping) -----

feature_tenants <- contents %>%
  select(contentHash, runtimeFeatures) %>%
  mutate(runtimeFeatures = lapply(runtimeFeatures, function(x) as.character(unlist(x)))) %>%
  unnest_longer(runtimeFeatures) %>%
  filter(!is.na(runtimeFeatures)) %>%
  left_join(scripts %>% select(tenantId, contentHash), by = "contentHash",
            relationship = "many-to-many") %>%
  distinct(tenantId, runtimeFeatures) %>%
  count(runtimeFeatures, name = "tenants") %>%
  arrange(desc(tenants))

# ---- 6. Example plots -------------------------------------------------------

p_portability <- ggplot(portability_summary,
                        aes(x = reorder(bucket, contents), y = contents)) +
  geom_col(fill = "steelblue") +
  geom_text(aes(label = contents), hjust = -0.15, size = 3.5) +
  coord_flip(clip = "off") +
  scale_y_continuous(expand = expansion(mult = c(0, 0.15))) +
  labs(x = "Portability bucket",
       y = "Distinct script contents (deduplicated)",
       title = "Distinct script contents by portability bucket") +
  thesis_theme()
save_plot(p_portability, "portability_bucket.png")
p_portability

p_packages <- ggplot(head(package_tenants, 15),
                     aes(x = reorder(package, tenants), y = tenants)) +
  geom_col(fill = "steelblue") +
  geom_text(aes(label = tenants), hjust = -0.15, size = 3.5) +
  coord_flip(clip = "off") +
  scale_y_continuous(expand = expansion(mult = c(0, 0.15))) +
  labs(x = "Package", y = "Tenants (customers)",
       title = "Top 15 packages by tenant count") +
  thesis_theme()
save_plot(p_packages, "top_packages.png")
p_packages

# Drop the CommonJS module-wrapper bookkeeping entries here: they are near
# universal (every script gets one) and crowd out the features that are
# actually informative, process.env and Buffer in particular.
feature_tenants_plot <- feature_tenants %>%
  filter(!startsWith(runtimeFeatures, "commonjs:")) %>%
  slice_max(tenants, n = 20)

p_features <- ggplot(feature_tenants_plot,
                     aes(x = reorder(runtimeFeatures, tenants), y = tenants)) +
  geom_col(fill = "steelblue") +
  geom_text(aes(label = tenants), hjust = -0.15, size = 3.5) +
  coord_flip(clip = "off") +
  scale_y_log10(breaks = c(1, 5, 10, 50, 100, 500),
                expand = expansion(mult = c(0, 0.15))) +
  labs(x = "Runtime feature", y = "Tenants (customers), log scale",
       title = "Node runtime feature usage by tenant",
       subtitle = "General overview. CommonJS module bookkeeping omitted (near-universal).\nFor the V8-viability argument specifically, see the two-panel chart in section 7d.") +
  thesis_theme()
save_plot(p_features, "runtime_features.png")
p_features

# ---- 7. V8 viability: can this tenant population drop Node.js? -------------
# Reframes the portability bucket as a per-tenant question. A tenant that has
# 50 self-contained scripts and one script touching fs still cannot drop
# Node, so each tenant is classified by its single HARDEST script, not by
# content in isolation.

bucket_levels <- c("self-contained", "packages-only", "node-globals",
                   "node-builtins", "dynamic-code", "unknown")

# scripts_bucketed already exists from section 3 (per-script bucket, joined
# from content_bucket, with unmatched contentHashes falling back to "unknown")

tenant_hardest <- scripts_bucketed %>%
  mutate(bucket = factor(bucket, levels = bucket_levels, ordered = TRUE)) %>%
  group_by(tenantId) %>%
  summarise(hardest = max(bucket)) %>%
  ungroup()

tenant_hardest_counts <- tenant_hardest %>%
  count(hardest, name = "tenants") %>%
  mutate(share = tenants / sum(tenants)) %>%
  arrange(hardest)

print(tenant_hardest_counts)

total_tenants <- nrow(tenant_hardest)
v8_naive <- tenant_hardest %>%
  filter(hardest %in% c("self-contained", "packages-only")) %>%
  nrow()

cat(sprintf("\nLayer 1, no shims at all: %d / %d tenants (%.1f%%)\n",
            v8_naive, total_tenants, 100 * v8_naive / total_tenants))

# ---- 7a. Are the node-globals-hardest tenants shimmable with just
#          process.env and Buffer, the two features the writeup calls
#          shimmable? -----------------------------------------------------

SHIMMABLE <- c("process.env", "node:Buffer")

node_globals_hashes <- content_bucket %>%
  filter(bucket == "node-globals") %>%
  pull(contentHash)

node_globals_features <- contents %>%
  filter(contentHash %in% node_globals_hashes) %>%
  select(contentHash, runtimeFeatures) %>%
  mutate(runtimeFeatures = lapply(runtimeFeatures, function(x) as.character(unlist(x)))) %>%
  unnest_longer(runtimeFeatures) %>%
  filter(!is.na(runtimeFeatures), !startsWith(runtimeFeatures, "commonjs:"))

tenant_globals_used <- node_globals_features %>%
  left_join(scripts %>% select(tenantId, contentHash), by = "contentHash",
            relationship = "many-to-many") %>%
  inner_join(tenant_hardest %>% filter(hardest == "node-globals") %>% select(tenantId),
             by = "tenantId") %>%
  distinct(tenantId, runtimeFeatures) %>%
  group_by(tenantId) %>%
  summarise(shimmable_only = all(runtimeFeatures %in% SHIMMABLE)) %>%
  ungroup()

shimmable_only_count <- sum(tenant_globals_used$shimmable_only)
v8_with_light_shims <- v8_naive + shimmable_only_count

cat(sprintf("Layer 2, plus process.env/Buffer polyfill: %d / %d tenants (%.1f%%)\n",
            v8_with_light_shims, total_tenants,
            100 * v8_with_light_shims / total_tenants))

# ---- 7b. Hard floor: tenants touching an OS-level builtin anywhere,
#          not just as their hardest script. fs, https and friends need
#          real host bindings, not a JS-level polyfill. -------------------

HARD_BUILTINS <- c("fs", "https", "http", "net", "tls", "dns", "dgram",
                   "child_process", "os", "tty", "readline", "v8",
                   "perf_hooks", "diagnostics_channel", "cluster",
                   "worker_threads")

builtin_tenants <- imports %>%
  filter(category == "builtin") %>%
  left_join(scripts %>% select(tenantId, contentHash), by = "contentHash",
            relationship = "many-to-many") %>%
  distinct(tenantId, package)

builtin_module_tenants <- builtin_tenants %>%
  count(package, name = "tenants") %>%
  arrange(desc(tenants))

print(builtin_module_tenants)

tenant_builtin_hardness <- builtin_tenants %>%
  group_by(tenantId) %>%
  summarise(touches_hard = any(package %in% HARD_BUILTINS)) %>%
  ungroup()

n_any_builtin <- n_distinct(builtin_tenants$tenantId)
n_hard_floor  <- sum(tenant_builtin_hardness$touches_hard)
n_soft_only   <- n_any_builtin - n_hard_floor

cat(sprintf(
  "\nHard floor: %d / %d tenants touch an OS-level builtin (fs/https/net/...) somewhere\n",
  n_hard_floor, total_tenants))
cat(sprintf(
  "%d tenants touch a builtin but only from the polyfillable set (path, buffer, util, ...)\n",
  n_soft_only))

# ---- 7c. Transitive dependency check: resolved, not just flagged ----------
# A script that only imports an npm package can still end up needing a real
# Node builtin, if that package reaches for one internally. The scan cannot
# see this, it only records what a script directly requires. Rather than
# leave this as a caveat, the packages actually carrying tenant weight were
# downloaded and their published Node entry point (package.json "main" /
# "exports"."."."require", or the actual requires in the shipped dist/lib
# file when "main" pointed at a bundle) was read directly. First pass done
# 2026-09-08 (4 fetch packages); extended 2026-09-09 to cover every package
# with >=1 tenant that plausibly does network I/O (mail, cloud-identity,
# cloud-storage, and database-driver packages), 22 packages total.
#
# FETCH_HTTP_BUILTIN: packages whose Node build calls require('http') /
# require('https') (or the "node:" equivalents) itself, bypassing any
# fetch() the host provides. Confirmed by reading the shipped source:
#   axios@1.20.0                        dist/node/axios.cjs      http/https/zlib/...
#   node-fetch@3.3.2                    src/index.js             node:http, node:https
#   isomorphic-fetch@3.0.0              fetch-npm-node.js         thin wrapper over node-fetch
#   ofetch@1.5.1                        dist/node.cjs            via node-fetch-native -> node:http/https
#   got@16.0.0                          dist/source/core/index.js node:http
#   undici@8.10.2                       lib/core/connect.js       node:net, node:tls (TCP socket layer under its fetch())
#   httpntlm@1.8.13                     httpntlm.js               http, https
#   nodemailer@10.0.1                   dist/cjs/fetch/index.js   node:http, node:https, node:net (SMTP + its own fetch helper)
#                                        dist/cjs/mailer/index.js  node:net (raw SMTP socket)
#   @sendgrid/mail@8.1.6                depends on @sendgrid/client -> uses https
#   @azure/msal-node@6.0.0              lib/msal-node.cjs         http
#   @microsoft/microsoft-graph-client@3 depends on @azure/msal-node transitively for auth network calls
#   aws-sdk@2.1693.0                    lib/http/node.js          http, https
#   follow-redirects@1.16.0             index.js                  http, https
#   simple-oauth2@5.1.0                 lib/client/client.js      via @hapi/wreck -> http, https directly
# A tenant using any of these cannot drop to bare V8 without a real host
# binding for network access (fetch/socket), regardless of which
# portability bucket their script landed in.
FETCH_HTTP_BUILTIN <- c("axios", "node-fetch", "isomorphic-fetch", "ofetch", "got",
                        "undici", "httpntlm", "nodemailer", "@sendgrid/mail",
                        "@azure/msal-node", "@microsoft/microsoft-graph-client",
                        "aws-sdk", "follow-redirects", "simple-oauth2")

# TCP_ONLY_BUILTIN: packages that need a raw TCP (or TLS-over-TCP) socket,
# not HTTP at all, most of them database or mail-protocol client drivers
# talking their own binary wire protocol. Confirmed by reading the shipped
# source:
#   mssql@12.7.1        depends on tedious (its default driver)
#   tedious@20.0.0       lib/connector.js, lib/message-io.js   net, tls (TDS protocol)
#   mysql2@3.24.4        lib/base/connection.js                net, tls
#   mysql@2.18.1         lib/Connection.js                     net
#   oracledb@7.0.1       lib/thin/sqlnet/ntTcp.js               net, tls (thin-mode SQL*Net)
#   kafkajs@2.2.4        src/network/socketFactory.js           net, tls
#   imapflow@2.0.0       dist/cjs/imap-flow.js                  net, tls (IMAP protocol)
#   ftp@0.3.10           lib/connection.js                      net
# These need a host TCP/TLS socket binding, not an HTTP client; a fetch()
# polyfill does not help them at all.
TCP_ONLY_BUILTIN <- c("mssql", "tedious", "mysql2", "mysql", "oracledb",
                      "kafkajs", "imapflow", "ftp")

# FETCH_SHIMMABLE: packages that only call the global fetch() function and
# never require a Node builtin directly, so a fetch() polyfill is enough.
# Confirmed the same way: @dvelop-sdk/{dms,business-objects,identityprovider,
# task} all depend only on @dvelop-sdk/core, whose lib/http/fetch.js source
# calls the bare global `fetch(...)`, no require('http') anywhere in the
# package. express, node-forge, fuse.js, xmlbuilder, xml2js, jsonwebtoken,
# lodash, moment, uuid were also checked and confirmed to do no network I/O
# of their own (express expects the *caller's* script to hold the
# http.Server, which the scan already sees directly as usesNodeBuiltins).
FETCH_SHIMMABLE <- c("@dvelop-sdk/dms", "@dvelop-sdk/business-objects",
                     "@dvelop-sdk/identityprovider", "@dvelop-sdk/task",
                     "@dvelop-sdk/core")

TRANSITIVE_CHECKED <- c(FETCH_HTTP_BUILTIN, TCP_ONLY_BUILTIN, FETCH_SHIMMABLE)

bare_tenant_pkg <- imports %>%
  filter(category == "bare") %>%
  left_join(scripts %>% select(tenantId, contentHash), by = "contentHash",
            relationship = "many-to-many") %>%
  distinct(tenantId, package)

n_npm_tenants <- n_distinct(bare_tenant_pkg$tenantId)
n_npm_pairs   <- nrow(bare_tenant_pkg)
n_checked_tenants <- bare_tenant_pkg %>% filter(package %in% TRANSITIVE_CHECKED) %>%
  distinct(tenantId) %>% nrow()
n_checked_pairs <- bare_tenant_pkg %>% filter(package %in% TRANSITIVE_CHECKED) %>% nrow()

cat(sprintf(
  "\nTransitive dependency coverage: %d of %d npm packages checked cover %d / %d\n",
  length(TRANSITIVE_CHECKED), n_distinct(bare_tenant_pkg$package),
  n_checked_pairs, n_npm_pairs))
cat(sprintf(
  "tenant-package pairs (%.1f%%), reaching %d / %d npm-using tenants (%.1f%%).\n",
  100 * n_checked_pairs / n_npm_pairs, n_checked_tenants, n_npm_tenants,
  100 * n_checked_tenants / n_npm_tenants))

fetch_http_tenants <- bare_tenant_pkg %>% filter(package %in% FETCH_HTTP_BUILTIN) %>%
  distinct(tenantId) %>% pull(tenantId)
tcp_only_tenants <- bare_tenant_pkg %>% filter(package %in% TCP_ONLY_BUILTIN) %>%
  distinct(tenantId) %>% pull(tenantId)
fetch_hard_tenants <- union(fetch_http_tenants, tcp_only_tenants)

cat(sprintf(
  "\nOf the transitively-confirmed-hard tenants: %d need HTTP/fetch, %d need a raw TCP/TLS socket\n",
  length(fetch_http_tenants), length(tcp_only_tenants)))
cat(sprintf(
  "(%d need both, e.g. a script mailing via nodemailer and querying via mssql in different scripts).\n",
  length(intersect(fetch_http_tenants, tcp_only_tenants))))

# tenants whose npm packages are entirely outside the checked set: their
# transitive status is genuinely unresolved, not assumed safe
transitive_unresolved_tenants <- bare_tenant_pkg %>%
  group_by(tenantId) %>%
  summarise(only_unchecked = all(!package %in% TRANSITIVE_CHECKED)) %>%
  filter(only_unchecked) %>%
  pull(tenantId)

cat(sprintf(
  "%d tenants use only npm packages outside the checked set: transitive status unresolved.\n",
  length(transitive_unresolved_tenants)))

# ---- 7c-2. Recomputed hard floor, including the confirmed fetch-family
#            transitive requirement, reconciled against the direct-builtin
#            hard floor from 7b so exactly one number survives. ------------

new_hard_floor_tenants <- union(builtin_tenants %>%
  filter(package %in% HARD_BUILTINS) %>% pull(tenantId) %>% unique(),
  fetch_hard_tenants)

n_hard_floor_updated <- length(new_hard_floor_tenants)

cat(sprintf(
  "\nHard floor, direct builtins only (7b): %d / %d tenants (%.1f%%)\n",
  n_hard_floor, total_tenants, 100 * n_hard_floor / total_tenants))
cat(sprintf(
  "Hard floor, direct + confirmed transitive fetch-family: %d / %d tenants (%.1f%%)\n",
  n_hard_floor_updated, total_tenants, 100 * n_hard_floor_updated / total_tenants))

# ---- 7c-3. Transition matrix: old classification vs. new, so a reader
#            sees exactly which tenants moved and from where, rather than
#            reading a jump in the headline number as a computation error.
#            "old" is the §5.1 hardest-bucket verbatim (all six buckets,
#            self-contained/packages-only/node-globals/node-builtins/
#            dynamic-code/unknown), so this table's row totals reproduce
#            the tenant_hardest_counts numbers exactly and a reviewer can
#            check them side by side. "new" adds the transitive fetch-
#            family finding and splits node-builtins into its hard subset
#            (fs/https/...) versus its soft subset (path/util/... only,
#            which stays polyfillable, not "unknown").

direct_hard_tenants <- builtin_tenants %>% filter(package %in% HARD_BUILTINS) %>%
  pull(tenantId) %>% unique()

transition <- tenant_hardest %>%
  mutate(old_class = as.character(hardest)) %>%
  mutate(
    new_class = case_when(
      tenantId %in% new_hard_floor_tenants ~ "hard-floor",
      old_class == "node-globals" ~ "shimmable (node-globals)",
      old_class == "node-builtins" ~ "shimmable (soft builtins only)",
      old_class %in% c("self-contained", "packages-only") ~ "V8-viable (layer 1)",
      TRUE ~ "unknown"
    )
  )

transition_matrix <- transition %>% count(old_class, new_class, name = "tenants") %>%
  arrange(factor(old_class, levels = bucket_levels), desc(tenants))

cat("\nTransition matrix, §5.1 portability bucket -> post transitive-dependency class:\n")
print(transition_matrix)

# old-axis row totals must reproduce §5.1 exactly (446/569/505/171/3/24)
stopifnot(all(sort(transition %>% count(old_class) %>% pull(n)) ==
              sort(tenant_hardest_counts$tenants)))
stopifnot(sum(transition$new_class == "hard-floor") == n_hard_floor_updated)
stopifnot(sum(transition_matrix$tenants) == total_tenants)

write.csv(transition_matrix, "transition_matrix.csv", row.names = FALSE)

# ---- 7c-4. Viability as an interval, not a point estimate ------------------
# Both bounds are restricted to the layer-1 population (self-contained +
# packages-only, the only tenants "no shims" was ever claiming for), so
# they answer the same question at two different confidence levels instead
# of drifting onto a different, larger population. node-globals tenants
# need a shim by definition and parse-failure tenants were never counted
# as no-shims-viable in the first place, so neither belongs in this
# interval; they are separate, already-reported numbers (Layer 2, and the
# unknown bucket in §5.1).
#
# Lower bound: of the 1,015 layer-1 tenants, drop everyone who either (a)
# is confirmed to hit a hard transitive dependency (fetch-family), or (b)
# has an unresolved transitive status (uses only npm packages outside the
# 9 checked). This is "viable only where the evidence is complete."
#
# Upper bound: drop only the confirmed blockers (a); every unresolved
# tenant (b) is assumed to resolve favorably. This is the ceiling the
# transitive-dependency check cannot currently rule out.

layer1_tenants <- tenant_hardest %>%
  filter(hardest %in% c("self-contained", "packages-only")) %>% pull(tenantId)

confirmed_viable_tenants <- setdiff(layer1_tenants,
  union(fetch_hard_tenants, transitive_unresolved_tenants))
optimistic_ceiling_tenants <- setdiff(layer1_tenants, fetch_hard_tenants)

lower_bound <- length(confirmed_viable_tenants)
upper_bound <- length(optimistic_ceiling_tenants)

stopifnot(upper_bound == v8_naive - length(intersect(layer1_tenants, fetch_hard_tenants)))
stopifnot(lower_bound <= upper_bound)

parse_fail_hashes <- raw %>% filter(type == "error") %>% pull(contentHash)
parse_fail_tenants <- scripts %>% filter(contentHash %in% parse_fail_hashes) %>%
  distinct(tenantId) %>% nrow()
node_globals_tenant_count <- tenant_hardest %>% filter(hardest == "node-globals") %>% nrow()

cat(sprintf(
  "\nNo-shims viability interval (layer 1 only): %d / %d (%.1f%%) confirmed viable\n",
  lower_bound, total_tenants, 100 * lower_bound / total_tenants))
cat(sprintf(
  "up to %d / %d (%.1f%%) if all %d transitive-unresolved layer-1 tenants turn out fine.\n",
  upper_bound, total_tenants, 100 * upper_bound / total_tenants,
  length(intersect(layer1_tenants, transitive_unresolved_tenants))))
cat(sprintf(
  "(%d parse-failure tenants and %d node-globals tenants are reported separately, not folded into this interval.)\n",
  parse_fail_tenants, node_globals_tenant_count))

# ---- 7c-5. Unit sensitivity: tenant vs. script level, and how much of the
#            hard floor hinges on a single script ---------------------------
# The tenant-level hard floor answers "how many customers are blocked."
# A separate question a reviewer will ask is how fragile that count is: is
# a tenant blocked because every script it stores needs a hard builtin, or
# because exactly one script out of many does? "Hard" is evaluated per
# SCRIPT here (does this specific content import a HARD_BUILTIN, a
# FETCH_HTTP_BUILTIN/TCP_ONLY_BUILTIN package, or use dynamic code), not
# per tenant, so a tenant with 20 clean scripts and 1 fs script counts as
# 1 hard script out of 20, not 20 out of 20.
#
# No invocation-count telemetry exists in this dataset (all.ndjson has no
# call/exec/volume field), so a usage-weighted number cannot be produced;
# script-count is the nearest available substitute.

hard_content_hashes <- union(
  union(
    imports %>% filter(category == "builtin", package %in% HARD_BUILTINS) %>% pull(contentHash),
    imports %>% filter(category == "bare", package %in% c(FETCH_HTTP_BUILTIN, TCP_ONLY_BUILTIN)) %>% pull(contentHash)
  ),
  content_bucket %>% filter(bucket == "dynamic-code") %>% pull(contentHash)
) %>% unique()

hard_scripts_per_tenant <- scripts_bucketed %>%
  filter(tenantId %in% new_hard_floor_tenants) %>%
  mutate(is_hard_script = contentHash %in% hard_content_hashes) %>%
  group_by(tenantId) %>%
  summarise(total_scripts = n(), hard_scripts = sum(is_hard_script)) %>%
  ungroup()

n_single_script_blockers <- hard_scripts_per_tenant %>%
  filter(hard_scripts == 1, total_scripts > 1) %>% nrow()

cat(sprintf(
  "\nOf %d hard-floor tenants, %d are blocked by exactly one script out of a larger population\n",
  nrow(hard_scripts_per_tenant), n_single_script_blockers))
cat(sprintf(
  "(median scripts per hard-floor tenant: %.0f; median hard scripts per hard-floor tenant: %.0f).\n",
  median(hard_scripts_per_tenant$total_scripts), median(hard_scripts_per_tenant$hard_scripts)))
cat("No per-tenant invocation/call-volume telemetry exists in this dataset,",
    "so a call-weighted number cannot be computed; script-count is the nearest proxy.\n")

# ---- 7d. Plots ---------------------------------------------------------
# Every chart here shares VIABILITY_COLORS (defined in section 0), so red
# always means "hard floor", blue always means "V8 viable", amber always
# means "shimmable but not free", across all three figures below.

tenant_hardest_plot <- tenant_hardest_counts %>%
  mutate(group = case_when(
    hardest %in% c("self-contained", "packages-only") ~ "V8 viable",
    hardest == "node-globals" ~ "shimmable (mostly)",
    hardest %in% c("node-builtins", "dynamic-code") ~ "hard floor",
    hardest == "unknown" ~ "unresolved"
  ))

p_tenant_hardest <- ggplot(tenant_hardest_plot,
                           aes(x = hardest, y = tenants, fill = group)) +
  geom_col() +
  geom_text(aes(label = tenants), vjust = -0.4, size = 3.5) +
  scale_fill_manual(values = VIABILITY_COLORS, name = NULL) +
  labs(x = "Tenant's single hardest Node dependency",
       y = "Tenants (customers)",
       title = "Tenants by their hardest Node dependency") +
  thesis_theme() +
  theme(legend.position = "bottom")
save_plot(p_tenant_hardest, "tenant_hardest.png")
p_tenant_hardest

p_builtin_modules <- ggplot(
  head(builtin_module_tenants, 15) %>%
    mutate(group = if_else(package %in% HARD_BUILTINS, "hard floor",
                           "shimmable (mostly)")),
  aes(x = reorder(package, tenants), y = tenants, fill = group)
) +
  geom_col() +
  geom_text(aes(label = tenants), hjust = -0.15, size = 3.5) +
  coord_flip(clip = "off") +
  scale_y_continuous(expand = expansion(mult = c(0, 0.15))) +
  scale_fill_manual(values = VIABILITY_COLORS, name = NULL) +
  labs(x = "Node builtin module", y = "Tenants (customers)",
       title = "Node builtin usage: hard floor vs. polyfillable") +
  thesis_theme() +
  theme(legend.position = "bottom")
save_plot(p_builtin_modules, "builtin_modules.png")
p_builtin_modules

# The two-panel replacement for the old single 29-bar feature chart, scoped
# to exactly the question this section is arguing: what actually blocks a
# V8-only runtime. Left panel: the two globals that a light polyfill fixes.
# Right panel: builtins split by whether they need real OS bindings.

feature_shimmable_plot <- feature_tenants %>%
  filter(runtimeFeatures %in% SHIMMABLE) %>%
  mutate(group = "shimmable (mostly)")

p_shimmable <- ggplot(feature_shimmable_plot,
                      aes(x = reorder(runtimeFeatures, tenants), y = tenants,
                          fill = group)) +
  geom_col() +
  geom_text(aes(label = tenants), hjust = -0.15, size = 3.5) +
  coord_flip(clip = "off") +
  scale_y_continuous(expand = expansion(mult = c(0, 0.15))) +
  scale_fill_manual(values = VIABILITY_COLORS, guide = "none") +
  labs(x = NULL, y = "Tenants (customers)",
       title = "Dominant shimmable globals") +
  thesis_theme()

p_builtins_panel <- ggplot(
  head(builtin_module_tenants, 10) %>%
    mutate(group = if_else(package %in% HARD_BUILTINS, "hard floor",
                           "shimmable (mostly)")),
  aes(x = reorder(package, tenants), y = tenants, fill = group)
) +
  geom_col() +
  geom_text(aes(label = tenants), hjust = -0.15, size = 3.5) +
  coord_flip(clip = "off") +
  scale_y_continuous(expand = expansion(mult = c(0, 0.15))) +
  scale_fill_manual(values = VIABILITY_COLORS, name = NULL) +
  labs(x = NULL, y = "Tenants (customers)",
       title = "Top 10 builtins, hard floor vs. shimmable") +
  thesis_theme() +
  theme(legend.position = "bottom")

p_v8_blockers <- p_shimmable + p_builtins_panel +
  plot_annotation(
    title = "What actually blocks a V8-only runtime",
    subtitle = "CommonJS module bookkeeping omitted: it is near-universal and not a real blocker"
  )
save_plot(p_v8_blockers, "v8_blockers.png", width = 12, height = 5)
p_v8_blockers

# ---- 8. Policy-driven reclassification --------------------------------------
# Some blockers aren't a V8-vs-Node question at all, they're things we would
# disallow in a tenant script regardless of which engine runs it. Excluding
# them from the viability calculation keeps the two questions separate:
# "can this run on V8" and "do we even want to allow this." Reclassifying a
# script's need this way is a policy decision this team is making, not a
# fact the scan hands over, so it belongs in a clearly named, editable list.

library(purrr)

POLICY_EXCLUDED_BUILTINS <- c("child_process", "readline", "tty", "v8", "perf_hooks")
# dynamic code (eval/Function/dynamic require) is excluded by policy too,
# handled separately below since it isn't a builtin import.

# How many tenants are running something we'd disallow today, independent
# of the V8 question? Worth reporting on its own, it's a remediation list.
policy_builtin_tenants <- imports %>%
  filter(category == "builtin", package %in% POLICY_EXCLUDED_BUILTINS) %>%
  left_join(scripts %>% select(tenantId, contentHash), by = "contentHash",
            relationship = "many-to-many") %>%
  distinct(tenantId) %>%
  pull(tenantId)

dynamic_code_tenants <- tenant_hardest %>%
  filter(hardest == "dynamic-code") %>%
  pull(tenantId)

policy_flagged_tenants <- union(policy_builtin_tenants, dynamic_code_tenants)

cat(sprintf(
  "\nTenants running something policy-excluded today (child_process, readline, tty, v8, perf_hooks or dynamic code), independent of the V8 question: %d\n",
  length(policy_flagged_tenants)))

# ---- 8a. Recompute the portability bucket ignoring policy-excluded needs --
# A content item that only touches a policy-excluded builtin (say, only
# readline) doesn't actually need a real Node builtin to satisfy, we're not
# providing readline either way, so it shouldn't count as "needs
# node-builtins" for the V8 decision. Same logic for dynamic code: it's
# dropped from the ladder entirely rather than given its own bucket.

content_builtin_modules <- imports %>%
  filter(category == "builtin") %>%
  group_by(contentHash) %>%
  summarise(modules = list(unique(package)), .groups = "drop")

content_bucket_policy <- contents %>%
  left_join(content_builtin_modules, by = "contentHash") %>%
  mutate(
    has_non_policy_builtin = map_lgl(
      modules, ~ !is.null(.x) && any(!.x %in% POLICY_EXCLUDED_BUILTINS)),
    usesNodeBuiltins_adj = usesNodeBuiltins & has_non_policy_builtin,
    bucket_policy = case_when(
      usesNodeGlobals      ~ "node-globals",
      usesNodeBuiltins_adj ~ "node-builtins",
      usesPackages         ~ "packages-only",
      selfContained        ~ "self-contained",
      TRUE ~ "unknown"
    )
  ) %>%
  select(contentHash, bucket_policy)

policy_bucket_levels <- c("self-contained", "packages-only", "node-globals",
                          "node-builtins", "unknown")

scripts_bucketed_policy <- scripts %>%
  left_join(content_bucket_policy, by = "contentHash") %>%
  mutate(bucket_policy = if_else(is.na(bucket_policy), "unknown", bucket_policy))

tenant_hardest_policy <- scripts_bucketed_policy %>%
  mutate(bucket_policy = factor(bucket_policy, levels = policy_bucket_levels,
                                ordered = TRUE)) %>%
  group_by(tenantId) %>%
  summarise(hardest = max(bucket_policy)) %>%
  ungroup()

tenant_hardest_policy_counts <- tenant_hardest_policy %>%
  count(hardest, name = "tenants") %>%
  mutate(share = tenants / sum(tenants))

v8_naive_policy <- tenant_hardest_policy %>%
  filter(hardest %in% c("self-contained", "packages-only")) %>%
  nrow()

cat(sprintf(
  "\nBefore policy exclusion: %d / %d tenants V8-viable with no shims (%.1f%%)\n",
  v8_naive, total_tenants, 100 * v8_naive / total_tenants))
cat(sprintf(
  "After policy exclusion:  %d / %d tenants V8-viable with no shims (%.1f%%)\n",
  v8_naive_policy, total_tenants, 100 * v8_naive_policy / total_tenants))

# ---- 8b. Before/after comparison table and plot -----------------------

comparison <- bind_rows(
  tenant_hardest_counts %>% mutate(hardest = as.character(hardest),
                                   view = "before policy exclusion"),
  tenant_hardest_policy_counts %>% mutate(hardest = as.character(hardest),
                                          view = "after policy exclusion")
) %>%
  mutate(hardest = factor(hardest, levels = c(
    "self-contained", "packages-only", "node-globals",
    "node-builtins", "dynamic-code", "unknown")))

print(comparison)

p_policy_comparison <- ggplot(comparison,
                              aes(x = hardest, y = tenants, fill = view)) +
  geom_col(position = position_dodge(width = 0.7), width = 0.6) +
  geom_text(aes(label = tenants),
            position = position_dodge(width = 0.7), vjust = -0.4, size = 3) +
  scale_fill_manual(values = c(
    "before policy exclusion" = "grey60",
    "after policy exclusion"  = "steelblue"
  ), name = NULL) +
  labs(x = "Tenant's single hardest requirement",
       y = "Tenants (customers)",
       title = "Effect of excluding disallowed behavior from the V8 question",
       subtitle = "child_process, readline, tty, v8, perf_hooks and dynamic code no longer\ncount against V8 viability, since we would block them under Node too") +
  thesis_theme() +
  theme(legend.position = "bottom")
save_plot(p_policy_comparison, "policy_comparison.png", width = 9, height = 5.5)
p_policy_comparison