# Monter les trois bases de données du projet text-to-SQL

Ce guide explique comment restaurer les trois sources de données de Calorvia SA à partir des fichiers `.sql` fournis : un ERP sur SQL Server et deux bases PostgreSQL (comptabilité et paie). Tout tourne dans Docker.

| Source | Moteur | Base | Port sur votre machine | Fichier |
|---|---|---|---|---|
| ERP GesPro 7 | SQL Server 2022 | `GESPRO` | 1433 | `sql/01_erp_gespro_sqlserver.sql` |
| Comptabilité | PostgreSQL 16 | `compta` | 5433 | `sql/02_compta_postgres.sql` |
| Paie | PostgreSQL 16 | `paie` | 5434 | `sql/03_paie_postgres.sql` |

Les ports 5433 et 5434 évitent le conflit avec le PostgreSQL du cours (journalisation), qui utilise déjà 5432.

## 1. Avant de commencer

### Ce qu'il faut sur la machine

- Docker avec Docker Compose v2 (`docker compose version` doit répondre).
- 4 Go de mémoire libre : SQL Server demande au moins 2 Go à lui seul.
- Environ 3 Go d'espace disque pour les images.

### Télécharger les images à l'avance

La connexion de la salle est lente. Si les images vous sont fournies sur clé USB, chargez-les avec :

```bash
docker load -i mssql-server-2022.tar
docker load -i postgres-16.tar
```

Pour préparer ces fichiers sur une machine bien connectée :

```bash
docker pull mcr.microsoft.com/mssql/server:2022-latest
docker pull postgres:16
docker save -o mssql-server-2022.tar mcr.microsoft.com/mssql/server:2022-latest
docker save -o postgres-16.tar postgres:16
```

### Mac avec puce Apple (M1 à M4)

L'image SQL Server n'existe qu'en x86-64. Dans Docker Desktop, activez « Use Rosetta for x86_64/amd64 emulation on Apple Silicon » (Settings, General). Le fichier `docker-compose.yml` force déjà `platform: linux/amd64`.

## 2. Arborescence

```
sources_calorvia/
├── docker/
│   ├── docker-compose.yml
│   ├── .env.example
│   ├── sqlserver/restore_erp.sh       restauration de l'ERP avec sqlcmd
│   └── postgres/00_create_role.sh     création du compte en lecture seule
├── sql/
│   ├── 01_erp_gespro_sqlserver.sql
│   ├── 02_compta_postgres.sql
│   └── 03_paie_postgres.sql
└── fiches_paie/AAAA-MM/*.pdf          fiches de paie (chemin stocké dans la base paie)
```

Gardez cette structure : le fichier `docker-compose.yml` monte les scripts avec des chemins relatifs (`../sql/...`).

## 3. Configuration

```bash
cd sources_calorvia/docker
cp .env.example .env
```

Ouvrez `.env` et changez les mots de passe :

| Variable | Rôle |
|---|---|
| `MSSQL_SA_PASSWORD` | Administrateur SQL Server (`sa`). Au moins 8 caractères avec trois des quatre catégories : majuscule, minuscule, chiffre, symbole. Sinon SQL Server refuse de démarrer. |
| `PG_ADMIN_USER`, `PG_ADMIN_PASSWORD` | Administrateur des deux PostgreSQL. |
| `AGENT_RO_PASSWORD` | Mot de passe du compte `agent_ro`, créé dans les trois bases, en lecture seule. C'est ce compte que votre agent doit utiliser. |

Le fichier `.env` ne doit jamais aller dans Git : ajoutez-le à votre `.gitignore`.

## 4. Démarrer

```bash
docker compose up -d
docker compose ps
```

Que se passe-t-il ?

1. Les deux PostgreSQL démarrent. Au premier démarrage seulement, ils exécutent les fichiers montés dans `/docker-entrypoint-initdb.d` : d'abord `00_create_role.sh` (création de `agent_ro`), puis le script SQL. Comptez une minute.
2. SQL Server démarre. Quand il répond (healthcheck), le conteneur `erp-restore` exécute le script avec `sqlcmd`, puis s'arrête. Comptez deux à trois minutes.

Suivre la restauration de l'ERP :

```bash
docker compose logs -f erp-restore
```

La dernière ligne doit être `GESPRO restored.` Le conteneur `calorvia-erp-restore` a ensuite le statut `Exited (0)` : c'est normal.

## 5. Vérifier

### SQL Server

`sqlcmd` est présent dans l'image SQL Server :

```bash
docker exec -it calorvia-erp /opt/mssql-tools18/bin/sqlcmd -S localhost -U agent_ro -P 'Lecture#Seule2026' -C \
  -d GESPRO -Q "SELECT COUNT(*) AS factures FROM VTE_FACT"
```

L'option `-C` fait confiance au certificat auto-signé du serveur. Sans elle, la connexion échoue avec une erreur de certificat.

### PostgreSQL

```bash
docker exec -it calorvia-compta psql -U agent_ro -d compta -c "SELECT COUNT(*) FROM ecriture"
docker exec -it calorvia-paie psql -U agent_ro -d paie -c "SELECT COUNT(*) FROM payslips"
```

### Résultats attendus

| Requête | Résultat |
|---|---|
| `SELECT COUNT(*) FROM VTE_FACT` (GESPRO) | 10 185 |
| `SELECT COUNT(*) FROM ecriture` (compta) | 20 562 |
| `SELECT COUNT(*) FROM payslips` (paie) | 7 298 |

### Le compte agent_ro est bien en lecture seule

Ces commandes doivent échouer :

```bash
docker exec -it calorvia-compta psql -U agent_ro -d compta -c "DELETE FROM budget"
# ERROR:  cannot execute DELETE in a read-only transaction

docker exec -it calorvia-erp /opt/mssql-tools18/bin/sqlcmd -S localhost -U agent_ro -P 'Lecture#Seule2026' -C \
  -d GESPRO -Q "DELETE FROM PAR_CODE"
# The DELETE permission was denied on the object 'PAR_CODE'...
```

Dans la base `paie`, `agent_ro` ne peut pas lire les colonnes `national_number`, `iban` et `street_address` de la table `employees` : `SELECT * FROM employees` est refusé, il faut nommer les colonnes.

## 6. Comment ça marche

### PostgreSQL : le dossier d'initialisation

L'image officielle `postgres` exécute, dans l'ordre alphabétique, les fichiers `*.sh`, `*.sql` et `*.sql.gz` présents dans `/docker-entrypoint-initdb.d`. Elle le fait une seule fois, quand le dossier de données est vide. D'où les préfixes `00_` et `10_` dans `docker-compose.yml` : le rôle doit exister avant que le script lui donne des droits.

Conséquence : si vous modifiez un script ou le mot de passe après le premier démarrage, rien ne se passe. Il faut supprimer le volume :

```bash
docker compose down -v      # supprime les conteneurs ET les volumes (données perdues)
docker compose up -d
```

### SQL Server : pas de dossier d'initialisation

L'image SQL Server n'a pas d'équivalent de `docker-entrypoint-initdb.d`. On utilise donc un second conteneur, `erp-restore`, qui :

1. attend que le serveur réponde (`depends_on` avec `condition: service_healthy`) ;
2. vérifie dans `sys.databases` si `GESPRO` existe déjà ;
3. sinon, exécute le script :

```bash
sqlcmd -S erp-sqlserver -U sa -P "$MSSQL_SA_PASSWORD" -C -b -f 65001 \
       -v AGENT_RO_PASSWORD="$AGENT_RO_PASSWORD" -i /restore/01_erp_gespro_sqlserver.sql
```

| Option | Rôle |
|---|---|
| `-C` | Accepter le certificat auto-signé. |
| `-b` | S'arrêter à la première erreur et renvoyer un code d'erreur. |
| `-f 65001` | Lire le fichier en UTF-8. Sans cette option, les accents sont abîmés (« SociÃ©tÃ© »). |
| `-v AGENT_RO_PASSWORD=...` | Remplacer `$(AGENT_RO_PASSWORD)` dans le script : le mot de passe n'est pas écrit dans le fichier SQL. |
| `-i` | Fichier à exécuter. Les lignes `GO` séparent les lots d'instructions (c'est une commande de sqlcmd, pas du SQL). |

Pour restaurer à nouveau l'ERP sans toucher aux PostgreSQL :

```bash
FORCE_RESTORE=1 docker compose up erp-restore
```

Le script commence par supprimer la base `GESPRO` si elle existe, puis la recrée.

## 7. Sans docker compose : les commandes à la main

Utile pour comprendre ce que fait Compose, ou pour restaurer dans un serveur existant.

### SQL Server

```bash
docker run -d --name erp -e ACCEPT_EULA=Y -e MSSQL_SA_PASSWORD='Calorvia#Sa2026' \
  -p 1433:1433 --platform linux/amd64 mcr.microsoft.com/mssql/server:2022-latest

# attendre que le serveur soit prêt (environ 20 secondes), puis copier et exécuter le script
docker cp sql/01_erp_gespro_sqlserver.sql erp:/tmp/gespro.sql
docker exec -it erp /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'Calorvia#Sa2026' -C -b -f 65001 \
  -v AGENT_RO_PASSWORD='Lecture#Seule2026' -i /tmp/gespro.sql
```

### PostgreSQL

```bash
docker run -d --name compta -e POSTGRES_USER=calorvia -e POSTGRES_PASSWORD='Calorvia#Pg2026' \
  -e POSTGRES_DB=compta -p 5433:5432 postgres:16

docker exec -i compta psql -U calorvia -d compta -c "CREATE ROLE agent_ro LOGIN PASSWORD 'Lecture#Seule2026'"
docker exec -i compta psql -U calorvia -d compta -v ON_ERROR_STOP=1 < sql/02_compta_postgres.sql
```

`-v ON_ERROR_STOP=1` arrête psql à la première erreur ; sans cette option, psql continue et affiche des dizaines d'erreurs en cascade. Si le rôle `agent_ro` n'existe pas, le script le crée sans mot de passe ; ajoutez-en un ensuite avec `ALTER ROLE agent_ro PASSWORD '...'`.

Le même script fonctionne dans un PostgreSQL installé localement (version 14 ou plus récente) : créez la base, le rôle, puis `psql -d compta -v ON_ERROR_STOP=1 -f sql/02_compta_postgres.sql`.

## 8. Se connecter depuis Python

```bash
uv add pymssql "psycopg[binary]" sqlalchemy
```

`pymssql` est plus simple à installer que `pyodbc`, qui demande le pilote ODBC de Microsoft.

```python
import os

import psycopg
import pymssql

erp = pymssql.connect(server="localhost", port=1433, user="agent_ro",
                      password=os.environ["AGENT_RO_PASSWORD"], database="GESPRO")
with erp.cursor(as_dict=True) as cur:
    cur.execute("SELECT TOP 5 CLI_CODE, CLI_NOM FROM CLI_CLIENT ORDER BY CLI_ID")
    print(cur.fetchall())

compta = psycopg.connect(host="localhost", port=5433, dbname="compta", user="agent_ro",
                         password=os.environ["AGENT_RO_PASSWORD"])
with compta.cursor() as cur:
    cur.execute("SELECT code_journal, COUNT(*) FROM ecriture GROUP BY 1")
    print(cur.fetchall())
```

Avec SQLAlchemy (pratique pour polars ou LangChain) :

```python
from sqlalchemy import create_engine

erp = create_engine("mssql+pymssql://agent_ro:MOT_DE_PASSE@localhost:1433/GESPRO")
compta = create_engine("postgresql+psycopg://agent_ro:MOT_DE_PASSE@localhost:5433/compta")
paie = create_engine("postgresql+psycopg://agent_ro:MOT_DE_PASSE@localhost:5434/paie")
```

Si le mot de passe contient des caractères spéciaux (`#`, `@`, `/`), encodez-le dans l'URL avec `urllib.parse.quote_plus`.

Pour un client graphique : DBeaver gère SQL Server et PostgreSQL. Pour SQL Server, cochez « Trust server certificate » dans les propriétés du pilote.

### Depuis un autre conteneur

Si votre agent tourne lui aussi dans Docker, `localhost` désigne le conteneur de l'agent. Utilisez le nom du service (`erp-sqlserver`, `compta-postgres`, `paie-postgres`) et le port interne (1433 ou 5432) en mettant l'agent sur le même réseau Compose, ou `host.docker.internal` avec les ports publiés.

## 9. Les fiches de paie

La table `payslips` contient `pdf_path`, un chemin relatif comme `fiches_paie/2026-05/M10405_2026-05.pdf`. Les PDF ne sont pas dans la base : ils sont dans le dossier `fiches_paie` livré à côté. Si votre agent doit les lire ou les renvoyer, montez ce dossier en lecture seule dans son conteneur (`- ../fiches_paie:/data/fiches_paie:ro`).

Ces fiches contiennent des données personnelles (fictives, mais traitez-les comme réelles).

## 10. Dépannage

| Symptôme | Cause probable et solution |
|---|---|
| `calorvia-erp` redémarre en boucle | Mot de passe `sa` trop simple. Lisez `docker logs calorvia-erp`, changez `MSSQL_SA_PASSWORD`, puis `docker compose down -v`. |
| `erp-restore` : `Login failed for user 'sa'` | Le mot de passe de `.env` a changé après la création du volume. `docker compose down -v`. |
| `erp-restore` : `'AGENT_RO_PASSWORD' scripting variable not defined` | Variable absente de `.env`. |
| `erp-restore` : `Incorrect syntax near ...` à la création du login | Le mot de passe `AGENT_RO_PASSWORD` contient une apostrophe : il est inséré tel quel dans le script SQL. Choisissez-en un autre. |
| `Login failed for user 'agent_ro'` sur SQL Server après un changement de mot de passe | Le login est créé une seule fois au niveau du serveur ; une nouvelle restauration ne change pas son mot de passe. `docker compose down -v` ou `ALTER LOGIN agent_ro WITH PASSWORD = '...'` avec le compte `sa`. |
| `exec format error` ou SQL Server très lent sur Mac | Activer Rosetta dans Docker Desktop (voir section 1). |
| `Bind for 0.0.0.0:1433 failed: port is already allocated` | Un autre SQL Server tourne. Changez le port publié (`"14330:1433"`). |
| PostgreSQL vide ou sans `agent_ro` | Le volume existait déjà : les scripts d'initialisation n'ont pas été rejoués. `docker compose down -v`. |
| Accents illisibles dans l'ERP | Script exécuté sans `-f 65001`. Restaurez à nouveau avec `FORCE_RESTORE=1`. |
| `SSL Provider: certificate verify failed` | Ajouter `-C` à sqlcmd, « Trust server certificate » dans DBeaver. |
| `permission denied for table employees` | Normal pour `SELECT *` : nommez les colonnes autorisées. |
