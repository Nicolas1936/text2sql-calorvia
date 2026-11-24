# Sources de données Calorvia SA (projet text-to-SQL)

| Dossier ou fichier | Contenu |
|---|---|
| `guide_restauration_sources.md` | Comment monter les trois bases avec Docker, vérifier et se connecter. À lire en premier. |
| `presentation_sources_calorvia.md` | Ce que contiennent les bases, les liens entre elles, douze questions pour démarrer. |
| `docker/` | `docker-compose.yml`, `.env.example` et les scripts de restauration. |
| `sql/` | Les scripts des trois bases : ERP (SQL Server), comptabilité et paie (PostgreSQL). |
| `fiches_paie/` | Les 7 298 fiches de paie en PDF, référencées par `payslips.pdf_path` dans la base paie. |

Démarrage rapide :

```bash
cd docker
cp .env.example .env        # puis changer les mots de passe
docker compose up -d
docker compose logs -f erp-restore
```

Toutes les données sont fictives. Les fiches de paie et la table `employees` contiennent des données personnelles inventées : traitez-les comme si elles étaient réelles.
