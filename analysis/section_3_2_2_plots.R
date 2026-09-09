# section_3_2_2_plots.R
#
# Zwei Grafiken zugeschnitten auf Abschnitt 3.2.2 (Ergebnis der
# Bestandsanalyse), die genau die Zahlen aus Tabelle tab:blockierende-familien
# bebildern: 629 HTTP-Familie, 63 Socket-Familie, 44 Schnittmenge, 648
# Vereinigung, 713 Hard Floor gesamt, 90,9 % davon rein netzwerkbedingt.
#
# Unabhaengig aus all.ndjson hergeleitet (nicht aus scan_analysis.R
# ge-sourced), damit sich die Zahlen gegen den Kapiteltext verifizieren
# lassen, ohne dessen Konsolenausgaben/Seiteneffekte mitzuschleppen.
#
# Aufruf: Rscript section_3_2_2_plots.R  (erwartet all.ndjson im selben Ordner)

library(jsonlite)
library(dplyr)
library(tidyr)
library(ggplot2)

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
save_plot <- function(plot, filename, width = 8, height = 5) {
  ggsave(filename, plot, width = width, height = height, dpi = 300)
}

FAMILY_COLORS <- c(
  "HTTP-Familie"       = "steelblue",
  "Socket-Familie"     = "firebrick",
  "beide"              = "#e69f00",
  "andere Blocker"     = "grey60",
  "Rest (kein Blocker)" = "grey85"
)

# ---- 1. Laden und Buckets wie in scan_analysis.R ----------------------------

raw <- stream_in(file("all.ndjson"))
scripts  <- raw %>% filter(type == "script")  %>% select(tenantId, contentHash)
contents <- raw %>% filter(type == "content") %>%
  select(contentHash, likelyMinified, usesDynamicCode, usesNodeBuiltins,
         usesNodeGlobals, usesPackages, selfContained)
imports  <- raw %>% filter(type == "import")  %>%
  select(contentHash, package, category)

minified_hashes <- contents %>% filter(likelyMinified) %>% pull(contentHash)
contents <- contents %>% filter(!contentHash %in% minified_hashes)
scripts  <- scripts  %>% filter(!contentHash %in% minified_hashes)
imports  <- imports  %>% filter(!contentHash %in% minified_hashes)

total_tenants <- n_distinct(scripts$tenantId)

# gleiche Listen wie scan_analysis.R Abschnitt 7c, per Quelltext bestaetigt
HARD_BUILTINS <- c("fs", "https", "http", "net", "tls", "dns", "dgram",
                   "child_process", "os", "tty", "readline", "v8",
                   "perf_hooks", "diagnostics_channel", "cluster",
                   "worker_threads")
FETCH_HTTP_BUILTIN <- c("axios", "node-fetch", "isomorphic-fetch", "ofetch", "got",
                        "undici", "httpntlm", "nodemailer", "@sendgrid/mail",
                        "@azure/msal-node", "@microsoft/microsoft-graph-client",
                        "aws-sdk", "follow-redirects", "simple-oauth2")
TCP_ONLY_BUILTIN <- c("mssql", "tedious", "mysql2", "mysql", "oracledb",
                      "kafkajs", "imapflow", "ftp")

bare_tenant_pkg <- imports %>%
  filter(category == "bare") %>%
  left_join(scripts, by = "contentHash", relationship = "many-to-many") %>%
  distinct(tenantId, package)

builtin_tenant_pkg <- imports %>%
  filter(category == "builtin") %>%
  left_join(scripts, by = "contentHash", relationship = "many-to-many") %>%
  distinct(tenantId, package)

http_tenants   <- bare_tenant_pkg %>% filter(package %in% FETCH_HTTP_BUILTIN) %>%
  distinct(tenantId) %>% pull(tenantId)
socket_tenants <- bare_tenant_pkg %>% filter(package %in% TCP_ONLY_BUILTIN) %>%
  distinct(tenantId) %>% pull(tenantId)
direct_hard_tenants <- builtin_tenant_pkg %>% filter(package %in% HARD_BUILTINS) %>%
  distinct(tenantId) %>% pull(tenantId)
dynamic_tenants <- contents %>% filter(usesDynamicCode) %>% pull(contentHash) %>%
  {scripts %>% filter(contentHash %in% .) %>% distinct(tenantId) %>% pull(tenantId)}

network_tenants <- union(http_tenants, socket_tenants)
hard_floor_tenants <- union(network_tenants, union(direct_hard_tenants, dynamic_tenants))

n_http    <- length(http_tenants)
n_socket  <- length(socket_tenants)
n_both    <- length(intersect(http_tenants, socket_tenants))
n_union   <- length(network_tenants)
n_hard    <- length(hard_floor_tenants)
n_other   <- n_hard - n_union

cat(sprintf("HTTP-Familie: %d, Socket-Familie: %d, Schnittmenge: %d, Vereinigung: %d\n",
            n_http, n_socket, n_both, n_union))
cat(sprintf("Hard Floor gesamt: %d / %d (%.1f%%), davon reine Netzwerkbindung: %d (%.1f%%)\n",
            n_hard, total_tenants, 100 * n_hard / total_tenants,
            n_union, 100 * n_union / n_hard))
stopifnot(n_http == 629, n_socket == 63, n_both == 44, n_union == 648, n_hard == 713)

# ---- Grafik 1: Zusammensetzung des Hard Floor ------------------------------
# Zerlegt die 713 Hard-Floor-Mandanten so, wie Tabelle tab:blockierende-familien
# es tut: HTTP-Familie allein, Socket-Familie allein, beide, und der Rest, der
# an etwas anderem als einer Netzwerkbindung scheitert (Dateisystem,
# Prozesserzeugung, dynamische Codeerzeugung).

composition <- tibble(
  gruppe = factor(
    c("HTTP-Familie", "Socket-Familie", "beide", "andere Blocker"),
    levels = c("andere Blocker", "beide", "Socket-Familie", "HTTP-Familie")
  ),
  mandanten = c(n_http - n_both, n_socket - n_both, n_both, n_other)
)

p_composition <- ggplot(composition, aes(x = "Hard Floor\n(713 Mandanten)",
                                          y = mandanten, fill = gruppe)) +
  geom_col(width = 0.5) +
  geom_text(aes(label = mandanten), position = position_stack(vjust = 0.5),
            size = 4, colour = "white", fontface = "bold") +
  scale_fill_manual(values = FAMILY_COLORS, name = NULL) +
  coord_flip() +
  labs(x = NULL, y = "Mandanten",
       title = "Woran der Hard Floor tatsächlich scheitert",
       subtitle = sprintf(
         "%d von %d blockierten Mandanten (%.1f %%) scheitern allein an einem Netzwerk-Binding",
         n_union, n_hard, 100 * n_union / n_hard)) +
  thesis_theme() +
  theme(legend.position = "bottom", axis.text.y = element_text(size = 12))
save_plot(p_composition, "hard_floor_zusammensetzung.png", width = 9, height = 4)

# ---- Grafik 2: Gesamtbestand, Viabilität und Hard Floor --------------------
# Ordnet die 713 Hard-Floor-Mandanten in den Gesamtbestand ein (1.718) und
# zeigt das Groessenverhaeltnis der beiden Familien nebeneinander, damit die
# im Text genannte Zehn-zu-eins-Relation direkt ablesbar ist.

overview <- tibble(
  gruppe = factor(c("Nicht blockiert", "Hard Floor"),
                  levels = c("Nicht blockiert", "Hard Floor")),
  mandanten = c(total_tenants - n_hard, n_hard)
)

p_overview <- ggplot(overview, aes(x = gruppe, y = mandanten, fill = gruppe)) +
  geom_col(width = 0.6) +
  geom_text(aes(label = sprintf("%d\n(%.1f %%)", mandanten, 100 * mandanten / total_tenants)),
            vjust = -0.3, size = 4) +
  scale_fill_manual(values = c("Nicht blockiert" = "steelblue",
                               "Hard Floor" = "firebrick"), guide = "none") +
  scale_y_continuous(expand = expansion(mult = c(0, 0.25))) +
  labs(x = NULL, y = "Mandanten",
       title = "Anteil des Hard Floor am Gesamtbestand",
       subtitle = sprintf("%d Mandanten insgesamt, Viabilitätsintervall 39,0–42,9 %%", total_tenants)) +
  thesis_theme()

families <- tibble(
  familie = factor(c("HTTP-Familie\n(axios u. a.)", "Socket-Familie\n(mssql u. a.)"),
                   levels = c("HTTP-Familie\n(axios u. a.)", "Socket-Familie\n(mssql u. a.)")),
  mandanten = c(n_http, n_socket)
)

p_families <- ggplot(families, aes(x = familie, y = mandanten, fill = familie)) +
  geom_col(width = 0.6) +
  geom_text(aes(label = mandanten), vjust = -0.3, size = 4) +
  scale_fill_manual(values = c("HTTP-Familie\n(axios u. a.)" = "steelblue",
                               "Socket-Familie\n(mssql u. a.)" = "firebrick"), guide = "none") +
  scale_y_continuous(expand = expansion(mult = c(0, 0.25))) +
  labs(x = NULL, y = "Mandanten",
       title = "Größenverhältnis der Blocker-Familien",
       subtitle = sprintf("etwa %.0f zu 1", n_http / n_socket)) +
  thesis_theme()

library(patchwork)
p_combined <- p_overview + p_families
save_plot(p_combined, "hard_floor_einordnung.png", width = 11, height = 4.5)

cat("\nGespeichert: hard_floor_zusammensetzung.png, hard_floor_einordnung.png\n")
