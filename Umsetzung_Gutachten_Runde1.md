# Umsetzung des Gutachtens, Runde 1

Stand: 2. November 2026. Abschnittsnummern nach der überarbeiteten Fassung.

## Pflichtänderungen

| Ref | Status | Wo |
|---|---|---|
| R1 | umgesetzt | 6.1 erster Absatz (Reichweite: M1 nur Entwurf/lokal, ohne Callout gemessen); Tab. 11 Beschriftung (M1 nur im Entwurf, T10) und Spalte „Herkunft“ (S1 „gemessen, ohne Callout“); 5.1 fehlender Callout als weitere Validitätsbedrohung auf dem Zuweisungspfad. Callout-Latenz nicht gemessen. |
| R2 | umgesetzt | 6.1, neuer Absatz nach U4: gezeigt vs. angenommen für das Agentenprofil, gleichzeitige Ausführungen nur durch die Isolate-Grenze getrennt |
| R3 | umgesetzt | 1.2 (Ausgangszustand hat Zustandsfreiheit selbst hergestellt, Evaluation misst gegen diesen Stand); 6.1 U3 beginnt mit „Unterschied allein bei M4“; Tab. 3 neue Zeile „Ausgangszustand am 30. Oktober, Worker-Thread je Ausführung“ |
| R4 | umgesetzt | Tab. 11: S6 „(Obergrenze)“, Herkunft „abgeleitet“; S7 ebenfalls „abgeleitet“. Scanner-Lauf nicht wiederholt. |
| R5 | umgesetzt (Kennzeichnung) | 5.4: Wert aus einem Lauf, vorläufig, bei Stufe 200 Nutzwert −0,2; Tab. 11 „Stufe 300/s verfehlt“, Herkunft „ein Lauf, vorläufig“; 6.1 U4 „in einem Lauf … verfehlte Stufe bei 300“. Keine Wiederholung. |
| R6 | umgesetzt | 4.3.4: Regeln stammen aus der Mandantenkonfiguration, Regeln aus dem Aufruf schränken sie nur ein (Schnittmenge im Gateway); 5.6: die Testregel im Agentenprofil kam aus dem Aufruf und wurde vom damaligen Stand ohne Schnittmenge übernommen. Schnittmenge im Gateway am 3. November umzusetzen. |

## Empfohlene Änderungen

| Ref | Status | Wo |
|---|---|---|
| S1 | Variante entfernt, Kanal gemessen | Ein Slot je Pod aus der Arbeit gestrichen (4.4, 5.2, 5.4, 6.1, Ausblick, Tab. „Stand je Beleg“). 4.4 nennt die Lücke bei gleichzeitigen Ausführungen weiter. 5.6 misst einen verdeckten Kanal zwischen gleichzeitigen Ausführungen (gleicher Pod gegen getrennte Pods auf einem Knoten), 4.3.5 beschreibt die Uhr mit virtueller Zeit bei Timern. 4.4 begründet, warum mehrere Slots bleiben, und nennt das Restrisiko (Zeitquellen über freigegebene Ziele, keine Begrenzung der Anfragen je Zeit, gemeinsamer Adressraum). Ausblick: dritte Frage zur Trennung nach Person. |
| S2 | umgesetzt | 1.2 SAND, Faastlane, Cloudflare-Blog (Bloom 2018); 4.1 Kata Containers; 4.3.2 SAND als Vorbild der zweistufigen Trennung. Vier neue Bib-Einträge. |
| S3 | umgesetzt | 3.4.3: T1–T8 standen vor der Umsetzung der Mechanismen fest; T9/T10 während der Evaluation |
| S4 | umgesetzt | 5.6 nach dem M3-Befund |
| S5 | umgesetzt | 3.3.1: Beleg [2] durch eigene Beobachtung mit Verweis auf T1 ersetzt |
| S6 | offen | Tabelle „Messskripte“ braucht Pfade und Commits |
| S7 | umgesetzt | 4.2.2: Entscheidung stützt sich auf die beiden übrigen Gründe |
| S8 | umgesetzt | 6.1 Grenzen-Absatz |
| S9 | umgesetzt | 6.2 Migrationspfad: Zustellversprechen festlegen, Startmarke als Option |
| S10 | teilweise | Pool-Vorhersage als nicht evaluiert in 4.4; Aufwandsschätzung `deno_core`-Ersatz offen |
| S11 | umgesetzt | Tab. 1 „T10 (während der Evaluation ergänzt)“; Tab. 3 Beschriftung erklärt M5 „offen“ und M1 „bedingt“ |
| S12 | umgesetzt | 2.2 Ack-Wait, Pull-Consumer, Leader (zwei neue NATS-Quellen); 5.1 Prometheus, cAdvisor, Tempo |
| S13 | teilweise | Kapitel 6 heißt „Fazit und Diffusion“; Titel bleibt |

## Redaktionelle Kleinigkeiten

| Nr. | Status |
|---|---|
| 1 | umgesetzt (5.6: „Ressourcenbegrenzung auf zwei Ebenen“ mit Verweis auf 6.2 statt „P5“) |
| 2 | teilweise (Tab. 24 „Objektspeicher“ statt „S3“); P1–P3 / A1–A3 als Laufnamen offen |
| 3 | offen (Grund für die fehlende Nummer S5 nötig) |
| 4–6 | offen (Layout nach Fertigstellung des Textes prüfen) |
| 7 | prüfen, ob Commit `e2ed36f` das abdeckt |
| 8 | offen (Angabe gegen [45] prüfen) |
| 9 | umgesetzt (1.2) |

## Zusätzlich

- 5.4: Satz ergänzt, dass der Prototyp unter Last mehr Speicher spart, als der Pool im Ruhezustand kostet (Reviewer 3).
- Die neue Quelle `the_nats_authors_clustering_2026` (URL der JetStream-Clustering-Doku) vor Abgabe im Browser prüfen.
