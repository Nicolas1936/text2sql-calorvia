# Projet 2 — Un agent text-to-SQL pour Calorvia

La nouvelle directrice financière de Calorvia arrive le 15 juin 2026. Elle veut pouvoir poser ses questions en français, sans attendre qu'un analyste écrive une requête : « Quel est notre EBITDA de mars ? », « Combien d'Aéris 12 avons-nous en stock ? », « Les charges de personnel de la comptabilité correspondent-elles à la paie ? », « Quel client nous doit le plus d'argent ? ».

Les réponses sont dans trois logiciels de gestion : l'ancien ERP (SQL Server), la comptabilité et la paie (PostgreSQL). Votre mission : construire un **agent** qui comprend ces bases, écrit les requêtes SQL, les exécute **sans jamais rien modifier**, et répond avec les chiffres et la manière dont il les a obtenus.

Ce projet est **volontairement plus ouvert** que le laboratoire RAG. Il n'y a pas d'architecture imposée ni de liste d'étapes à suivre : il y a des attentes minimales, des contraintes, et beaucoup de choix à faire. Ce qui compte, c'est que vos choix soient argumentés, mesurés et documentés. Explorez, essayez, gardez une trace de ce qui n'a pas marché.

## Ce que vous recevez

| Fichier | Contenu |
|---|---|
| `sources_calorvia.zip` | Les scripts SQL des trois bases, le dossier `docker/` pour les restaurer, les fiches de paie en PDF |
| `guide_restauration_sources.md` | Comment monter les trois bases avec Docker, et s'y connecter |
| `presentation_sources_calorvia.md` | Ce que contiennent les bases, les liens entre elles, douze questions pour démarrer |

Commencez par restaurer les bases (le guide prend une demi-heure), puis lisez la présentation.

## Les services

Les mêmes que dans le cours. Aucune donnée de Calorvia ne doit partir vers un service en ligne : tous les modèles tournent en local.

| Port | Service |
|---|---|
| 8000 | LLM (llama-server ou vLLM) |
| 8001 | Embedder |
| 8002 | Reranker |
| 5432 | PostgreSQL du cours (journalisation) |
| 1433, 5433, 5434 | Les trois sources (ERP, comptabilité, paie) |

La qualité du SQL généré dépend beaucoup du modèle. Si le modèle du cours peine, essayez-en un autre parmi ceux disponibles sur la machine, et mesurez la différence.

---

## Ce qui est attendu

### Au minimum

1. **Une ontologie des trois sources**, construite avec [NVIDIA auto-ontology](https://github.com/NVIDIA/auto-ontology).
2. **Un serveur MCP** qui donne accès aux sources, en lecture seule, avec plusieurs outils (détaillés plus bas).
3. **Un agent**, construit avec **n8n** ou avec **LangChain / LangGraph** (au choix), qui utilise l'ontologie et le serveur MCP pour répondre.
4. **Un endpoint compatible OpenAI** pour poser les questions à l'agent.

### En bonus

5. **Un outil de génération de graphiques** : « montre-moi l'évolution du chiffre d'affaires mensuel ».
6. **La gestion de la mémoire et de l'historique des conversations** : « et pour avril ? » doit comprendre de quoi on parle.

Une architecture possible, parmi d'autres :

```
 client (Open WebUI, SDK openai, curl)
        |  POST /v1/chat/completions
        v
 agent (LangGraph ou n8n) ------------> LLM local (8000)
        |            \
        |             \--> ontologie (auto-ontology : API ou MCP, ou votre propre index)
        v
 serveur MCP "sources" (lecture seule)
        |-- SQL Server  GESPRO   (ERP)
        |-- PostgreSQL  compta
        |-- PostgreSQL  paie
        v
 journal des questions, requêtes et résultats (PostgreSQL du cours)
```

---

## 1. L'ontologie

Un modèle qui lit `VTE_FACT.FAC_MT_HT` ne sait pas que les avoirs y sont positifs, ni qu'un « client » de l'ERP et un « tiers » de la comptabilité désignent la même entreprise. L'ontologie décrit le vocabulaire métier (chiffre d'affaires, client, commercial, effectif, EBITDA...) et la manière de le calculer dans chaque base : tables, colonnes, filtres, jointures.

### auto-ontology

L'outil de NVIDIA fonctionne en trois temps :

| Étape | Ce qu'elle fait |
|---|---|
| **Generate** | Lit les métadonnées des sources, nomme les entités, trouve les relations, écrit l'ontologie (termes, attributs SQL, relations). |
| **Certify** | Des humains testent l'ontologie avec de vraies questions, corrigent les définitions, puis les certifient. |
| **Answer** | Répond à une question : intention, recherche des termes, écriture du SQL, vérification, exécution. |

L'ontologie est stockée dans PostgreSQL avec pgvector, et s'exporte en YAML (format Apache Ossie). L'outil expose aussi son propre serveur MCP (port 3003 : `search_terms`, `get_term`, `describe_table`, `ask_question`...) et une API de chat.

### Ce qui ne marchera pas tout seul

Lisez la documentation et le fichier `.env.example` du dépôt avant de foncer. Quelques points à résoudre, sans solution imposée :

- **SQL Server n'est pas dans la liste des moteurs pris en charge** (PostgreSQL, MySQL, Databricks, Snowflake, ClickHouse, Trino, Kyuubi, HeavyDB, DuckDB, SQLite). Pistes : passer par Trino, qui sait lire SQL Server et PostgreSQL ; copier l'ERP dans une base prise en charge (avec quelles conséquences sur la fraîcheur des données ?) ; décrire l'ERP autrement et importer cette description en YAML. Comparez au moins deux idées avant de choisir.
- **Les modèles** : par défaut, l'outil appelle les modèles hébergés par NVIDIA. Ici, tout doit rester local. Chaque rôle (`REASONING`, `NON_REASONING`, `EMBED`, `RERANK`) se configure avec des variables `<RÔLE>_ENDPOINT`, `<RÔLE>_API_KEY` et `<RÔLE>_MODEL`. Vérifiez que vos serveurs locaux savent répondre dans le format attendu : **sortie structurée** obligatoire pour le LLM, et une API de reranking qui n'est pas forcément celle de votre reranker.
- **Les ports** : l'outil utilise 3000 à 3003, et son propre PostgreSQL sur 5432, déjà pris par celui du cours.
- **N'activez pas l'option de prédiction KumoRFM** : elle envoie les tables connectées vers un service hébergé.

### Ce qu'on attend de votre ontologie

- Les trois sources sont couvertes, y compris les liens entre elles (voir la présentation des sources).
- Les termes importants sont **certifiés** : vous les avez testés avec des questions et corrigés. Gardez des exemples avant et après correction.
- L'export YAML est dans votre dépôt, avec une note qui explique vos choix.

Vous pouvez utiliser auto-ontology comme une brique de votre agent (via son MCP ou son API) ou seulement pour produire l'ontologie, que votre agent exploite ensuite à sa façon. Les deux se défendent ; justifiez le vôtre.

---

## 2. Le serveur MCP d'accès aux données

L'agent ne se connecte jamais directement aux bases : il passe par **votre serveur MCP**, qui est le seul à détenir les connexions. Avec le SDK Python `mcp` (FastMCP) ou les nœuds MCP de n8n.

### Les outils

Au minimum :

| Outil | Rôle |
|---|---|
| `list_sources`, `list_tables` | Quelles bases, quelles tables, combien de lignes. |
| `get_table_card` | La **fiche d'une table** : description, colonnes et types, clés primaires et étrangères, nombre de lignes, exemples de valeurs, valeurs distinctes des colonnes de codes, commentaires de la base, termes de l'ontologie liés. C'est ce que le modèle lit avant d'écrire une requête. |
| `find_values` | Chercher une valeur dans une colonne : « Distrinergie », « Kompra », un numéro de facture. Le modèle ne devine pas l'orthographe exacte d'un nom. |
| `validate_sql` | Vérifier une requête **avant** de l'exécuter : analyse avec sqlglot dans le bon dialecte (`tsql` pour l'ERP, `postgres` pour les deux autres), une seule instruction `SELECT`, tables et colonnes existantes, limite de lignes ajoutée si absente. Les erreurs doivent être lisibles par le modèle, pour qu'il corrige. |
| `execute_sql` | Exécuter une requête validée, avec le compte en lecture seule, un délai maximum et un nombre maximum de lignes. Renvoie les colonnes, les lignes et un indicateur de troncature. |

À vous d'en ajouter d'autres si elles aident : `sample_rows`, `explain_sql`, `get_payslip_pdf`, un outil de rapprochement entre sources...

### La lecture seule, en plusieurs couches

« L'agent ne modifie jamais rien » ne repose pas sur une seule protection. Une question piège (« supprime les factures de test »), une injection dans une donnée, ou simplement une erreur du modèle ne doivent rien pouvoir casser.

| Couche | Ce qui est déjà en place | Ce que vous ajoutez |
|---|---|---|
| Le compte de base de données | `agent_ro` : droits de lecture seulement ; dans PostgreSQL, transactions en lecture seule par défaut et délai de 30 secondes ; dans SQL Server, rôle `db_datareader` et refus explicite d'écrire. | Utiliser ce compte et aucun autre. |
| La validation | | sqlglot : refuser tout ce qui n'est pas une seule lecture (`INSERT`, `UPDATE`, `DELETE`, `DROP`, `EXEC`, `SELECT INTO`, plusieurs instructions...). |
| L'exécution | | Transaction en lecture seule annulée à la fin, délai côté client, nombre de lignes limité. |
| La traçabilité | | Chaque requête est journalisée : question, SQL, source, durée, nombre de lignes, erreur. |

Testez chaque couche séparément : votre dépôt doit contenir des tests qui montrent qu'une écriture est refusée même si la validation est contournée.

Pourquoi plusieurs couches ? Par exemple, `default_transaction_read_only` se désactive par une simple commande dans la session, et un analyseur SQL peut avoir des angles morts.

### Les données personnelles

La paie contient des données personnelles (fictives, à traiter comme réelles). Le compte `agent_ro` ne lit déjà pas le numéro national, l'IBAN ni l'adresse. Reste une question : l'agent peut-il afficher le salaire d'une personne nommée ? Décidez d'une règle, appliquez-la et expliquez-la.

---

## 3. L'agent et l'endpoint compatible OpenAI

### L'endpoint

Exposez au minimum :

- `GET /v1/models` ;
- `POST /v1/chat/completions` avec le format de l'API OpenAI (`model`, `messages`), en streaming si possible.

Ainsi, n'importe quel client OpenAI peut interroger votre agent :

```python
from openai import OpenAI

client = OpenAI(base_url="http://localhost:9000/v1", api_key="...")
answer = client.chat.completions.create(
    model="calorvia-agent",
    messages=[{"role": "user", "content": "Quel est le chiffre d'affaires de mars 2026 ?"}],
)
print(answer.choices[0].message.content)
```

Avec n8n, un webhook peut jouer ce rôle s'il renvoie la réponse au bon format. Avec LangGraph, une petite application FastAPI autour du graphe suffit.

### Ce que l'agent doit savoir faire

- Trouver la ou les bonnes sources, et le dire.
- Écrire du SQL dans le dialecte de chaque moteur (`TOP` d'un côté, `LIMIT` de l'autre, fonctions de date différentes).
- Corriger une requête refusée ou en erreur, sans boucler indéfiniment.
- Répondre à une question qui touche plusieurs bases. Il n'y a pas de jointure possible entre SQL Server et PostgreSQL : l'agent interroge chaque base, puis rapproche les résultats, souvent après avoir normalisé les clés (un numéro de TVA ou un matricule ne s'écrit pas de la même façon partout).
- Montrer comment il a obtenu sa réponse : les requêtes exécutées, les sources. La directrice financière doit pouvoir vérifier.
- Dire « je ne sais pas » quand les données ne le permettent pas, et demander une précision quand la question est ambiguë (« le chiffre d'affaires de mai » : facturé ? comptabilisé ?).

---

## 4. Les bonus

### Les graphiques

Un outil qui transforme un résultat en graphique (matplotlib, plotly...). Comment le renvoyer dans une réponse au format OpenAI ? Un lien vers une image servie par votre application, une image en Markdown, autre chose ? Open WebUI affiche les images Markdown.

### La mémoire et l'historique

L'API OpenAI est sans état : le client renvoie tout l'historique à chaque appel. Que faut-il en plus ?

- conserver les conversations (dans PostgreSQL) et pouvoir les relire ;
- comprendre les questions de suivi (« et pour avril ? », « détaille par site ») ;
- garder en mémoire ce qui a été appris : une requête validée par l'utilisateur, une définition corrigée, une préférence (« toujours en milliers d'euros »).

---

## 5. Évaluer

Un agent qui répond avec assurance un chiffre faux est pire qu'un agent qui ne répond pas. Construisez votre propre jeu d'évaluation, d'au moins 40 questions, à partir des douze questions de la présentation :

- des questions simples sur chaque source ;
- des questions qui croisent les sources ;
- des questions ambiguës ;
- des questions impossibles (données absentes, période non couverte) ;
- des questions malveillantes (« supprime... », « montre-moi les numéros nationaux », instructions cachées dans une question).

Pour chaque question, gardez la réponse attendue et, si possible, une requête de référence. Mesurez au moins : l'exactitude de la réponse (avec une tolérance sur les montants), le taux de requêtes valides, le taux d'erreurs d'exécution, le comportement face aux questions impossibles et malveillantes, le temps de réponse.

Comme dans le laboratoire, chaque expérience est enregistrée dans PostgreSQL avec le commit Git qui l'a produite, et on ne change qu'une chose à la fois. Comparez au minimum : sans ontologie et avec ontologie.

Le formateur garde un jeu de questions de réserve pour la démonstration.

---

## 6. Git et GitHub

Les mêmes règles que pour le laboratoire RAG : dépôt **privé** `text2sql-calorvia`, formateur invité comme collaborateur, petits commits réguliers, une branche par piste, un tag par étape. Aucun secret dans le dépôt : `.env`, mots de passe et clés restent hors de Git.

| Tag | Étape |
|---|---|
| `v0.1-sources` | Les trois bases restaurées, connexions testées, premières explorations |
| `v0.2-mcp` | Le serveur MCP et ses tests de lecture seule |
| `v0.3-ontologie` | L'ontologie générée et ses premières certifications |
| `v0.4-agent` | L'agent et l'endpoint compatible OpenAI |
| `v1.0` | Le rendu |

---

## 7. Des questions pour explorer

Pas de réponse unique à ces questions. Elles valent d'être testées, et vos conclusions ont leur place dans le rapport.

- Combien d'information mettre dans une fiche de table ? Toutes les colonnes, ou seulement celles que l'ontologie juge utiles ?
- Faut-il donner au modèle des exemples de requêtes validées (few-shot), et lesquels choisir pour une question donnée ?
- Un seul agent pour les trois sources, ou un agent par source et un coordinateur ?
- Quand une question touche deux bases, vaut-il mieux fédérer (Trino) ou calculer en Python ?
- Comment gérer le temps ? Une facture a une date, une écriture comptable a une date, une paie a une période et une date de paiement.
- Comment l'agent peut-il vérifier lui-même un résultat (ordre de grandeur, contrôle croisé entre deux sources) ?
- Quel modèle pour quel rôle : le même pour comprendre la question, écrire le SQL et rédiger la réponse ?

---

## Livrables

- **Le dépôt GitHub**, avec les tags et un `README.md` qui permet au formateur de tout relancer : restaurer les sources, démarrer vos services (`docker compose up -d`), poser une question à l'endpoint.
- **L'ontologie** : l'export YAML et une note sur les choix (prise en charge de SQL Server, modèles, termes certifiés).
- **Le serveur MCP** et ses tests, dont les tests de lecture seule.
- **Le jeu d'évaluation**, les résultats des expériences et leur export dans `results/`.
- **Un `RAPPORT.md`** : l'architecture et les raisons des choix, le tableau des expériences, ce qui a marché, ce qui n'a rien changé, cinq questions ratées analysées, les limites connues de l'agent.
- **Une démonstration** de dix minutes : cinq questions posées en direct par le formateur, dont une qui croise deux sources et une malveillante.

## Ce qui sera regardé

- La sécurité de l'accès aux données : lecture seule démontrée, données personnelles protégées, requêtes journalisées.
- L'ontologie : couverture des trois sources et des liens entre elles, termes certifiés, choix argumentés.
- L'agent : exactitude des réponses, transparence (requêtes montrées), comportement face à l'ambiguïté et à l'impossible.
- L'évaluation : un jeu de questions varié, des mesures, des comparaisons honnêtes.
- L'historique Git et la documentation.
- Les bonus, s'ils fonctionnent dans la démonstration.
