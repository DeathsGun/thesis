# bundle_size_analysis.R
#
# Direct evidence for the transitive-dependency caveat in the V8 viability
# report (section 5.3): a script statically classified as "packages-only"
# can still be hiding a real Node dependency if the npm package it imports
# bundles one internally. Static import scanning of the customer's script
# can't see that. Comparing the size of the customer's own script.js
# against the size of the bundled bundle.js.zlib sitting in the same S3
# path gives a rough, but direct, signal: a bundle much bigger than the
# script it came from likely contains real inlined code, not nothing.
#
# Inputs, both expected in the working directory:
#   all.ndjson  - the scan's raw output
#   sizes.csv   - tenantId,scriptId,versionId,script_size,bundle_size
#                 no header row, produced separately via the AWS CLI
#
# This script is self-contained: it re-derives the portability bucket
# classification from all.ndjson rather than assuming scan_analysis.R was
# run first in the same session, so the two files can be run independently
# without one silently depending on leftover variables from the other.

library(jsonlite)
library(dplyr)
library(ggplot2)

# ---- 1. Rebuild just enough of the classification to know which scripts
#         are packages-only -------------------------------------------------

raw <- stream_in(file("all.ndjson"))

scripts <- raw %>%
  filter(type == "script") %>%
  select(tenantId, scriptId, versionId, contentHash)

contents <- raw %>%
  filter(type == "content") %>%
  select(contentHash, parsed, usesPackages, usesNodeBuiltins,
         usesNodeGlobals, usesDynamicCode, selfContained)

# Same precedence as scan_analysis.R section 3: node-globals overrides
# node-builtins when both are present, verified against the scan's
# published totals there. Only packages-only is actually used below, the
# rest of the ladder is kept so a script isn't miscounted as
# packages-only when it's really something harder.
content_bucket <- contents %>%
  mutate(bucket = case_when(
    !parsed          ~ "unknown",
    usesDynamicCode  ~ "dynamic-code",
    usesNodeGlobals  ~ "node-globals",
    usesNodeBuiltins ~ "node-builtins",
    usesPackages     ~ "packages-only",
    selfContained    ~ "self-contained",
    TRUE ~ "unknown"
  )) %>%
  select(contentHash, bucket)

# ---- 2. Load the sizes ------------------------------------------------------

sizes <- read.csv("sizes.csv", header = FALSE, colClasses = "character",
                  col.names = c("tenantId", "scriptId", "versionId",
                                "script_size", "bundle_size")) %>%
  mutate(
    script_size = as.numeric(script_size),
    bundle_size = as.numeric(bundle_size),
    has_bundle  = !is.na(bundle_size)
  )

cat(sprintf(
  "sizes.csv: %d rows, %d with no bundle.js.zlib found (%.1f%%)\n",
  nrow(sizes), sum(!sizes$has_bundle),
  100 * sum(!sizes$has_bundle) / nrow(sizes)))

# ---- 3. Join sizes to bucket, restricted to packages-only ------------------

sizes_bucketed <- sizes %>%
  filter(has_bundle, script_size > 0) %>%
  left_join(scripts, by = c("tenantId", "scriptId", "versionId")) %>%
  left_join(content_bucket, by = "contentHash") %>%
  mutate(bundle_ratio = bundle_size / script_size)

packages_only <- sizes_bucketed %>% filter(bucket == "packages-only")

# ---- 4. Flag tenants whose bundle is suspiciously large --------------------
# A ratio near 1 means the bundle is about the same size as the script,
# nothing much got inlined. A ratio well above 1 suggests real code, likely
# a dependency tree, got pulled in that the import scan never saw.
# FLAG_RATIO is a judgment call, not a fact, try a few values before
# committing to one in the report.

FLAG_RATIO <- 3

flagged <- packages_only %>%
  filter(bundle_ratio >= FLAG_RATIO) %>%
  arrange(desc(bundle_ratio))

cat(sprintf(
  "\n%d / %d packages-only tenants have a bundle at least %gx their script size\n",
  n_distinct(flagged$tenantId), n_distinct(packages_only$tenantId), FLAG_RATIO))

print(head(flagged %>%
             select(tenantId, scriptId, script_size, bundle_size, bundle_ratio),
           20))

# ---- 5. Plot -----------------------------------------------------------

p_bundle_ratio <- ggplot(packages_only, aes(x = bundle_ratio)) +
  geom_histogram(bins = 40, fill = "steelblue") +
  geom_vline(xintercept = FLAG_RATIO, linetype = "dashed", color = "firebrick") +
  scale_x_log10() +
  labs(x = "Bundle size / script size (log scale)",
       y = "Script versions",
       title = "How much bigger is the bundle than the script it came from?",
       subtitle = paste("packages-only bucket only. Dashed line: flagging",
                        "threshold used above")) +
  theme_minimal(base_size = 12)

ggsave("bundle_ratio.png", p_bundle_ratio, width = 8, height = 5, dpi = 300)
p_bundle_ratio