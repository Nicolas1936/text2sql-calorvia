# Projet text-to-SQL Calorvia : la marche à suivre

_État au 24 novembre 2026._

Le dossier ne contient encore que l'énoncé et les sources (`sources_calorvia/`). Il n'y a ni dépôt Git ni code, et les trois bases ne sont pas restaurées : aucun conteneur `calorvia-*`, aucun volume. La pile du projet RAG (`20-calorvia_rag_1`) est arrêtée : PostgreSQL sur 5432, embedder sur 8001, reranker sur 8002, llama-swap sur 8000.

L'énoncé n'impose pas d'étapes, mais les tags donnent un ordre. Cette liste le suit, et indique à chaque étape ce que tu peux reprendre du projet RAG.

## 0. Avant de commencer

1. **Le dépôt.**
   - Lance `git init`, puis crée sur GitHub un dépôt **privé** nommé exactement `text2sql-calorvia`, et invite le formateur dès le départ (dans le RAG, le dépôt était public et mal nommé).
   - Pose un premier tag `v0.0-empty_start`.
2. **`.gitignore`.** Reprends celui du RAG et ajoute :
   - `sources_calorvia/fiches_paie/` : 7 298 PDF de données personnelles ;
   - `sources_calorvia/sql/` : 31 Mo, fournis par le formateur ;
   - `sources_calorvia/docker/.env`.

   Le README dira où dézipper `sources_calorvia.zip`.
3. **Le port de l'ERP.** Le `docker-compose.yml` fourni publie SQL Server sur **14330**, alors que l'énoncé et le guide parlent de 1433. Choisis l'un ou l'autre, et note ton choix dans `.env.template` et dans le README.
4. **Le squelette Python**, repris du RAG.
   - Lance `uv init`. Dans `pyproject.toml`, mets dès le départ une vraie `description` et un `[project.scripts]` qui pointe vers un module existant (deux défauts du RAG corrigés seulement à la fin).
   - Reprends `config.py` (pydantic-settings et un TOML par expérience), `git_info.py` tel quel et `db.py`.
   - Crée un `.env.template` sans aucun secret.
5. **Les services du cours.**
   - Reprends `docker-compose.yml` et `config.yaml` (llama-swap) du RAG. Qdrant n'est plus utile.
   - Crée une base `calorvia_text2sql` dans le PostgreSQL du port 5432 : elle recevra le journal et les expériences.

## 1. Les sources (`feat/sources` → `v0.1-sources`)

1. **Restaure les trois bases** (section 4 du guide), puis vérifie le nombre de lignes : 10 185 factures, 20 562 écritures, 7 298 fiches de paie.
2. **Vérifie à la main les droits d'`agent_ro`.** Les deux `DELETE` du guide doivent être refusés, de même que `SELECT * FROM employees`. Garde la sortie de ces commandes pour le rapport.
3. **Les connexions** (`sources/connections.py`) : une par source, toujours avec `agent_ro` (pymssql pour l'ERP, psycopg pour les deux autres). Si le mot de passe contient `#` ou `@`, encode-le avec `quote_plus`.
4. **Le notebook d'exploration** (`notebooks/exploration_sources.ipynb`).
   - Pour chaque table : le nombre de lignes, les colonnes de codes et leurs valeurs, avec les libellés de `PAR_CODE`.
   - **L'ERP ne déclare aucune clé étrangère**, seulement des clés primaires. Déduis les liens des noms de colonnes (`CLI_ID`, `CDE_ID`, `VDR_ID`, `FAC_ID_ORIG`…) et note-les : ils serviront aux fiches de table.
   - **Les pièges à documenter.**
     - Les avoirs sont dans `VTE_FACT`, avec `FAC_TYPE = 'A'` (115 avoirs pour 10 070 factures). Leur montant est positif, et `FAC_ID_ORIG` renvoie à la facture d'origine.
     - Le statut des factures est dans `FAC_STATUT`.
     - Le budget a trois versions (`V1`, `V2`, `FINAL`).
     - Le journal `AN` contient les à-nouveaux.
     - Dans `payslip_lines`, les montants sont signés.
     - `payroll_runs` contient aussi des calculs de correction.
   - **Les clés de rapprochement n'ont pas le même format d'une base à l'autre.**
     - Le numéro de TVA s'écrit `BE0236099757` dans `CLI_CLIENT.CLI_TVA`, et `BE 0385.948.386` dans `tiers.numero_tva`.
     - Le matricule s'écrit `10405` dans `VDR_VENDEUR.VDR_MATRICULE`, et `M10405` dans `employees.employee_id`.
     - Les noms mélangent les majuscules et les minuscules (`Marchal`, `DEWIT`).
   - **Les périodes couvertes.** L'ERP va de janvier 2025 au 29 mai 2026, la comptabilité de janvier 2025 à mai 2026, la paie de juin 2025 à mai 2026. La date de référence est le **31 mai 2026** : c'est elle qui donne le sens de « en stock » ou « ce mois-ci ».
5. **Les douze questions de la présentation.** Pour chacune, écris une requête de référence qui retrouve la réponse attendue. Ce sera le début du jeu d'évaluation (`eval/questions.yaml`), et c'est la meilleure façon d'apprendre les bases.

Pose le tag `v0.1-sources` quand les connexions marchent et que les douze requêtes de référence retrouvent les réponses attendues.

## 2. Le serveur MCP (`feat/mcp` → `v0.2-mcp`)

Il s'écrit avec FastMCP (le SDK Python `mcp`). C'est le seul composant qui détient les connexions aux bases.

1. **Les outils.**
   - `list_sources` et `list_tables`, avec le nombre de lignes de chaque table.
   - `get_table_card` renvoie la fiche d'une table :
     - sa description, ses colonnes et leurs types ;
     - ses clés primaires et étrangères (pour l'ERP, les clés déduites à l'étape 1) ;
     - son nombre de lignes et des exemples de valeurs ;
     - les valeurs distinctes des colonnes de codes, avec leur libellé de `PAR_CODE` ;
     - les commentaires de PostgreSQL.

     Les termes de l'ontologie liés à la table s'ajouteront en `v0.3`. L'ERP n'a aucune documentation : écris ses descriptions à la main, dans un YAML.
   - `find_values` cherche une valeur sans tenir compte des majuscules ni des accents. Côté SQL Server, une collation `_CI_AI` ; côté PostgreSQL, `ILIKE` et une normalisation en Python ; ou bien `rapidfuzz` sur les valeurs distinctes gardées en cache. L'outil renvoie la table, la colonne et l'orthographe exacte.
   - `validate_sql` analyse la requête avec sqlglot dans le dialecte de la source (`tsql` pour l'ERP, `postgres` pour les deux autres).
     - Il exige une seule instruction, et que ce soit un `SELECT`.
     - Il vérifie les tables et les colonnes dans le catalogue.
     - Il ajoute `TOP` ou `LIMIT` s'il n'y en a pas.
     - Ses messages d'erreur doivent permettre au modèle de corriger, par exemple : « la colonne `FAC_MONTANT` n'existe pas dans `VTE_FACT` ; colonnes proches : `FAC_MT_HT`, `FAC_MT_TTC` ».
   - `execute_sql` valide la requête à nouveau, puis l'exécute dans une transaction en lecture seule, annulée à la fin, avec un délai côté client. Avec `fetchmany(max_rows + 1)`, tu sais si le résultat est tronqué.
   - D'autres outils peuvent aider : `sample_rows`, `explain_sql`, `get_payslip_pdf` (si ta règle sur les données personnelles le permet).
2. **Ce que la validation doit refuser, au minimum.**
   - `INSERT`, `UPDATE`, `DELETE`, `MERGE`, `DROP`, `ALTER`, `TRUNCATE`, `EXEC` et `EXECUTE`, `SELECT INTO`.
   - Plusieurs instructions dans la même requête.
   - Un CTE qui modifie des données : `WITH x AS (DELETE … RETURNING …) SELECT …` est valide en PostgreSQL.
   - `SET`, dont `SET default_transaction_read_only = off`.
   - `SELECT … FOR UPDATE` et `WAITFOR`.
   - Les fonctions dangereuses : `pg_sleep`, `pg_read_file`, `lo_import`, `dblink`, `xp_cmdshell`, `OPENROWSET`, `OPENQUERY`.

   Une liste blanche des types de nœuds sqlglot autorisés est plus sûre qu'une liste noire de mots-clés.
3. **L'exécution.**
   - Côté PostgreSQL : `BEGIN READ ONLY`, `SET LOCAL statement_timeout`, puis `ROLLBACK`.
   - Côté SQL Server : `SET LOCK_TIMEOUT`, un délai de requête dans le pilote, puis toujours `ROLLBACK`.
4. **Le journal.** Une table `query_log` reçoit, pour chaque requête : la question, la conversation, l'expérience, la source, le SQL proposé, le SQL exécuté, le résultat de la validation, la durée, le nombre de lignes, la troncature et l'erreur. Son schéma va dans `sql_queries/schema.sql`, comme dans le RAG.
5. **Les données personnelles.** Décide d'une règle, et applique-la dans le serveur, pas seulement dans le prompt.
   - Attention à la question 12 de la présentation (la commission de Joris Claes) : ta règle doit dire si elle reçoit une réponse.
   - Quelques règles possibles :
     - seulement des agrégats, sur au moins k personnes ;
     - le détail individuel pour un profil autorisé (la directrice financière), avec journalisation ;
     - les éléments variables comme les commissions, mais pas le salaire de base.
   - Écris la règle dans le README, et ajoute des questions de test qui la vérifient.
6. **Les tests** (`tests/`, avec pytest). Teste chaque couche séparément.
   - `test_validate.py` : toutes les requêtes du point 2 sont refusées, et les douze requêtes de référence sont acceptées.
   - `test_db_readonly.py` contourne la validation : il envoie `DELETE`, `UPDATE` et `DROP` directement à la connexion `agent_ro`, et la base doit les refuser. Fais-le aussi après `SET default_transaction_read_only = off` côté PostgreSQL : là, seul le `GRANT SELECT` protège encore, et le test doit le montrer.
   - `test_execute.py` : le délai dépassé (avec `pg_sleep`, en contournant la validation), la troncature, l'annulation de la transaction.
   - `test_pii.py` : `national_number`, `iban` et `street_address` restent illisibles, et ta règle sur les salaires est respectée.
   - `test_log.py` : chaque appel laisse une ligne dans le journal, y compris en cas d'erreur.

Pose le tag `v0.2-mcp` quand tous les tests passent.

## 3. L'ontologie (`feat/ontologie` → `v0.3-ontologie`)

1. **Clone [NVIDIA auto-ontology](https://github.com/NVIDIA/auto-ontology)** à côté de ton dépôt, pas dedans (ou en sous-module). Lis sa documentation et son `.env.example` **avant** de lancer quoi que ce soit.
2. **Les ports.** 3000 à 3003 sont libres sur la machine. Son PostgreSQL avec pgvector doit changer de port, par exemple **5435**, car 5432 à 5434 sont déjà pris.
3. **Les modèles, tous en local.** `REASONING_*` et `NON_REASONING_*` pointent vers llama-swap (8000), `EMBED_*` vers bge-m3 (8001), `RERANK_*` vers bge-reranker (8002). Avant de lancer Generate :
   - envoie au port 8000 une requête avec `response_format` de type `json_schema`, pour vérifier que la sortie structurée fonctionne : elle est obligatoire ;
   - cherche dans le code d'auto-ontology le format de l'API de reranking qu'il appelle. vLLM expose `/rerank`, au format Jina/Cohere. Si les deux formats diffèrent, écris un petit proxy FastAPI qui traduit ;
   - **n'active pas KumoRFM**.
4. **SQL Server n'est pas pris en charge.** Compare au moins deux pistes dans `ontology/NOTE.md`, par exemple dans un tableau comme celui-ci :

   | Piste | Pour | Contre |
   |---|---|---|
   | Trino (connecteurs `sqlserver` et `postgresql`) | Données à jour ; une seule porte d'entrée ; permet aussi les jointures entre sources | Un service de plus (JVM, mémoire) ; le SQL de l'ontologie est en dialecte Trino, pas en T-SQL |
   | Copie de l'ERP dans PostgreSQL | Rapide à mettre en place. Les données sont figées au 31 mai : la fraîcheur ne pose pas de problème ici, mais il faut l'expliquer | Dialecte et types différents (`TOP` contre `LIMIT`, `NVARCHAR`) ; copie à refaire si l'ERP change |
   | Description de l'ERP en YAML (format Ossie), importée | Aucune infrastructure de plus | Tout est à écrire à la main, sans profilage automatique |

   Quelle que soit la piste, l'agent interroge toujours le vrai SQL Server, par ton serveur MCP : l'ontologie décrit les données, elle ne les sert pas.
5. **Generate**, sur les trois sources, avec le compte `agent_ro`. Vérifie que le profilage de `employees` aboutit, puisque `SELECT *` y est refusé.
6. **Certify.** Dresse la liste des termes importants. Pour chacun : une ou plusieurs questions de test, la correction de la définition, puis la certification. **Garde un avant et un après** pour chaque correction, dans `ontology/certification.md`. Quelques termes :
   - le chiffre d'affaires facturé (dans l'ERP, avoirs déduits) et le chiffre d'affaires comptabilisé (classe 70, journal `VEN`) ;
   - le client de l'ERP et le tiers de la comptabilité ; le commercial et le vendeur ;
   - l'effectif sous contrat à une date ;
   - les charges de personnel (classe 62) ;
   - l'EBITDA et la marge d'EBITDA, les amortissements, le résultat net ;
   - la créance client ouverte (compte 400000 non lettré) ;
   - le stock ; le budget (version `FINAL`) ;
   - le télétravail, les absences, les commissions.
7. **Les liens entre les sources** (tableau de la section 4 de la présentation) doivent figurer dans l'ontologie, avec la manière de normaliser chaque clé.
8. **L'export YAML** va dans `ontology/calorvia_ontology.yaml`. La note `ontology/NOTE.md` explique tes choix : la piste pour SQL Server, les modèles, les termes certifiés, et la manière dont l'agent utilise l'ontologie.
9. **L'ontologie comme brique de l'agent, ou comme simple export ?** Deux options :
   - l'agent appelle le serveur MCP d'auto-ontology (port 3003 : `search_terms`, `get_term`…) ;
   - l'agent lit l'export YAML par ton propre serveur MCP : un outil `search_terms` sur un index bge-m3, et les termes liés ajoutés à `get_table_card`.

   La seconde option laisse moins de services à faire tourner pendant la démo et te garde la maîtrise du dialecte ; la première t'épargne un index à construire. Choisis, et justifie ton choix. Dans les deux cas, garde l'outil `ask_question` d'auto-ontology comme point de comparaison pour l'évaluation.

Pose le tag `v0.3-ontologie`.

## 4. L'agent et l'endpoint (`feat/agent` → `v0.4-agent`)

1. **LangGraph ou n8n ?** Tu as suivi les deux cours (`16-N8N`, `18-LongChain`, `19-FastAPI`). Je te conseille LangGraph avec FastAPI : l'évaluation automatique et les tests se font en Python, comme le serveur MCP. n8n serait plus rapide à montrer, mais plus difficile à évaluer.
2. **Le graphe**, à construire nœud par nœud.
   - **Comprendre la question** : l'intention, les sources concernées, la période.
     - Si la question est **ambiguë**, l'agent demande une précision (« le chiffre d'affaires facturé ou comptabilisé ? »).
     - Si les données ne permettent pas de répondre (période non couverte, donnée absente), il répond « je ne sais pas ».
   - **Chercher les termes** de l'ontologie, puis lire les fiches des tables concernées.
   - **Retrouver l'orthographe exacte** des noms propres avec `find_values` (Distrinergie, Kompra, V-2544).
   - **Écrire le SQL** dans le dialecte de la source et le valider avec `validate_sql`. En cas de refus ou d'erreur, corriger, **au plus N fois** (par exemple trois), puis l'exécuter avec `execute_sql`.
   - **Plusieurs sources** : une requête par base, puis le rapprochement des résultats en Python (`reconcile.py`), après normalisation des numéros de TVA et des matricules.
   - **Contrôler le résultat** : l'ordre de grandeur, et un contrôle croisé quand deux sources donnent le même chiffre (le chiffre d'affaires de l'ERP et celui de la comptabilité).
   - **Répondre** : le chiffre, les sources, **les requêtes exécutées**, et les hypothèses retenues (filtres, période).
3. **Le client MCP** : `langchain-mcp-adapters`. L'agent ne détient aucune connexion à une base.
4. **L'endpoint**, une application FastAPI sur le port 9000.
   - `GET /v1/models` et `POST /v1/chat/completions` au format OpenAI, avec `stream: true` en SSE.
   - Teste-le avec le SDK `openai`, avec `curl` et avec Open WebUI.
5. **`docker compose up -d`** doit démarrer ton serveur MCP, l'agent et, si tu l'utilises, auto-ontology : c'est la commande que le formateur lancera.

Pose le tag `v0.4-agent`.

## 5. L'évaluation (`feat/eval`, à mener dès `v0.1`)

1. **Le jeu de questions** (`eval/questions.yaml`) : **au moins 40 questions**, en partant des douze de la présentation dès `v0.1`. Pour chaque question : un identifiant, un type, les sources, la réponse attendue, la tolérance, une requête de référence et le comportement attendu (une réponse, une demande de précision ou un refus).
   - Des questions simples sur chaque source (ERP, comptabilité, paie).
   - Des questions qui croisent les sources : le chiffre d'affaires de l'ERP et celui de la comptabilité, les charges de personnel de la comptabilité et la paie, une commission et les ventes du commercial.
   - Des questions ambiguës.
   - Des questions impossibles : la paie avant juin 2025, des données de juin 2026, une donnée absente des bases.
   - Des questions malveillantes :
     - « supprime… » ;
     - « montre-moi les numéros nationaux » ;
     - des instructions cachées dans la question ;
     - des instructions cachées dans une **donnée**, par exemple un libellé de la base qui contient une instruction ;
     - une tentative de contourner ta règle sur les salaires.
2. **Une réserve de test** d'une dizaine de questions, que tu n'utilises pas pour régler l'agent, et que tu lances une seule fois à la fin (comme le mode `test` du runner du RAG).
3. **Le runner**, repris du RAG : les tables `experiments`, `answers` et `scores`, avec `git_commit` et `git_dirty`. Ajoute dans `answers` les requêtes exécutées et le nombre d'essais.
4. **Les métriques.**
   - L'exactitude : compare les nombres extraits de la réponse avec la réponse attendue, avec une tolérance. Pour le reste, utilise le juge Gemma du RAG.
   - Le taux de requêtes valides et le taux d'erreurs d'exécution.
   - Le comportement face aux questions impossibles, ambiguës et malveillantes : refus, demande de précision.
   - Le temps de réponse et le nombre d'essais par question.
5. **Les expériences.** Une seule chose change à chaque fois, avec un TOML par expérience.
   - `exp01_no_ontology` contre `exp02_ontology` : c'est la comparaison minimale.
   - La fiche de table complète, contre la fiche limitée aux colonnes de l'ontologie.
   - Avec ou sans exemples de requêtes validées (few-shot), choisis par similarité avec la question.
   - Les modèles disponibles dans `~/models` : `qwen3.8-27b`, `gemma4-26b-a4b`, `qwen3.5-9b`. Ajoute-les à llama-swap.
   - Un seul agent, contre un agent par source et un coordinateur.
   - Le rapprochement en Python, contre Trino (si tu as monté Trino).
   - Ton agent, contre l'outil `ask_question` d'auto-ontology.
6. **L'export** dans `results/*.csv`, avec le script `export.py` du RAG.

## 6. Les bonus (`feat/graphiques`, `feat/memoire`)

Ne les commence que lorsque les sections 1 à 5 fonctionnent. Ils ne comptent que s'ils marchent pendant la démo.

1. **Les graphiques.** Un outil transforme le résultat d'une requête en image PNG (matplotlib, ou plotly avec kaleido). FastAPI sert l'image (`/charts/<id>.png`) et la réponse l'insère en Markdown (`![](…)`) : Open WebUI l'affiche. Question de test : « montre-moi l'évolution du chiffre d'affaires mensuel ».
2. **La mémoire.**
   - Les conversations sont conservées dans PostgreSQL (tables `conversations` et `messages`) et peuvent être relues.
   - Les questions de suivi comme « et pour avril ? » sont réécrites en question complète, à l'aide de l'historique, avant le reste du graphe.
   - La mémoire durable garde ce qui a été appris : les requêtes validées par l'utilisateur (réutilisées comme exemples), les définitions corrigées, les préférences (« toujours en milliers d'euros »).
   - Ajoute au jeu d'évaluation des conversations de deux ou trois tours.

## 7. Le rapport, le README et la démo (`v1.0`)

1. **`RAPPORT.md`**, sur le modèle de celui du RAG : la méthode, le tableau comparatif, puis pour chaque expérience le changement testé, la comparabilité, les résultats, le diagnostic et la décision. Il doit aussi contenir :
   - l'architecture et les raisons de tes choix : la prise en charge de SQL Server, LangGraph ou n8n, l'ontologie comme brique ou comme export, la règle sur les données personnelles ;
   - les couches de la lecture seule, et les tests qui prouvent chacune ;
   - ce qui a marché, et ce qui n'a rien changé ;
   - **cinq questions ratées**. Pour chacune, l'étape où l'échec se situe (choix de la source, terme de l'ontologie, fiche de table, écriture du SQL, exécution, rapprochement, rédaction) et une piste de correction ;
   - les limites connues de l'agent ;
   - tes conclusions sur celles des questions de la section 7 de l'énoncé que tu as testées.
2. **`README.md`** : les prérequis, la restauration des sources, `docker compose up -d`, les ports, une question posée à l'endpoint, la commande de l'évaluation. Teste un **clone propre** dans un dossier vide, comme pour le RAG.
3. **La démonstration** dure dix minutes. Le formateur pose cinq questions en direct, dont une qui croise deux sources et une malveillante. Prépare :
   - Open WebUI branché sur `http://localhost:9000/v1` ;
   - une question d'échauffement, pour que le modèle soit chargé ;
   - le journal des requêtes ouvert, pour montrer la traçabilité ;
   - un graphique, si le bonus fonctionne.

## Pendant tout le projet

- Une branche par piste, fusionnée dans `main` une fois évaluée, puis le tag poussé avec `git push origin --tags`.
- Une expérience citée dans le rapport tourne sur du code commité (`git_dirty = false`).
- Des commits petits et réguliers, en anglais, à l'impératif, par exemple `Add sqlglot read-only validation`.
- Aucun secret dans Git : ni `.env`, ni mot de passe, ni clé. Le mot de passe d'`agent_ro` est lu dans `.env`, jamais écrit dans le code ni dans les tests.
- Garde une trace de ce qui n'a pas marché : l'énoncé le demande explicitement.

**Si le temps manque**, voici l'ordre de priorité :
1. la sécurité : la lecture seule démontrée par les tests, le journal, les données personnelles ;
2. un agent qui répond juste et montre ses requêtes ;
3. l'ontologie certifiée ;
4. l'évaluation sans et avec ontologie ;
5. les bonus.
