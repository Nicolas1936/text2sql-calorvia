# Les sources de données de Calorvia SA

Calorvia SA est l'entreprise fictive du laboratoire RAG : un fabricant belge de pompes à chaleur (gamme Aéris) et de groupes de ventilation (gamme Ventis). Siège à Namur, usines à Seneffe (pompes à chaleur) et à Gand (ventilation et entrepôt), bureau commercial à Lille, nouvel entrepôt à Herstal depuis le 18 mai 2026. Environ 620 personnes.

Pour ce projet, vous recevez les données de trois logiciels de gestion, extraites le **31 mai 2026**. Le lendemain, l'entreprise passe à un nouvel ERP (projet Atlas) : c'est la dernière photo de l'ancien système.

Les données sont fictives mais cohérentes entre elles et avec les documents du laboratoire RAG (chiffres d'affaires mensuels, prix, fournisseurs, événements comme le rappel des Aéris 12 ou l'ouverture de Herstal).

## Vue d'ensemble

| | ERP GesPro 7 | Comptabilité | Paie |
|---|---|---|---|
| Moteur | SQL Server 2022 | PostgreSQL 16 | PostgreSQL 16 |
| Base | `GESPRO` (schéma `dbo`) | `compta` | `paie` |
| Tables | 23 | 14 | 14 |
| Lignes | environ 139 000 | environ 101 000 | environ 218 000 |
| Période | janvier 2025 au 29 mai 2026 | janvier 2025 à mai 2026 | juin 2025 à mai 2026 |
| Noms des tables et colonnes | abréviations françaises en majuscules (`VTE_FACT`, `CLI_NOM`) | français (`ligne_ecriture`, `numero_compte`) | anglais (`payslips`, `gross_amount`) |
| Documentation dans la base | aucune | commentaires sur les tables et les colonnes | commentaires sur les tables seulement |

Comme souvent en entreprise, la documentation est incomplète. Cette présentation décrit les grandes lignes ; le détail se découvre en explorant les bases (c'est le rôle de l'ontologie que vous allez construire).

## 1. L'ERP GesPro 7 (SQL Server)

Un ERP ancien, utilisé depuis 2009. Les données antérieures à 2025 ont été archivées : les stocks de départ sont repris au 1er janvier 2025.

### Les tables par domaine

| Domaine | Tables | Contenu |
|---|---|---|
| Référentiels | `SOC_SITE`, `PAR_CODE` | Sites ; listes de codes (statuts, types, motifs) avec leur libellé. |
| Articles | `ART_FAMILLE`, `ART_ARTICLE`, `ART_TARIF`, `ART_NOMENC` | 62 articles : 8 produits finis, accessoires et pièces achetés pour la revente, composants et matières, prestations. Prix de vente par période (et prix spéciaux par client), nomenclatures des produits finis. |
| Tiers | `CLI_CLIENT`, `FRN_FOURNISSEUR`, `VDR_VENDEUR` | 380 fiches clients (distributeurs, installateurs, promoteurs), 17 fournisseurs d'articles, 13 commerciaux. |
| Ventes | `VTE_CDE`, `VTE_CDE_LIG`, `VTE_FACT`, `VTE_FACT_LIG` | Commandes clients, factures et avoirs. |
| Achats | `ACH_CDE`, `ACH_CDE_LIG`, `ACH_RECEP`, `ACH_RECEP_LIG`, `ACH_FACT` | Commandes aux fournisseurs, réceptions avec numéros de lot, factures des fournisseurs d'articles. |
| Production | `PRD_OF` | Ordres de fabrication : un par produit fini et par semaine, par ligne de production. |
| Stock | `STK_MVT`, `STK_ETAT` | Tous les mouvements de stock (quantités signées) et l'état du stock à la date d'extraction. |
| Logistique | `LOG_TRANSP`, `LOG_EXPED` | Transporteurs et expéditions (bons de livraison). |

### Les flux

- **Vente** : une commande (`VTE_CDE`) est expédiée (`LOG_EXPED`) et facturée le même jour (`VTE_FACT`). Une commande peut être livrée en plusieurs fois. Les avoirs sont dans la même table que les factures.
- **Achat** : une commande d'achat (`ACH_CDE`) donne une ou plusieurs réceptions (`ACH_RECEP`) puis une facture fournisseur (`ACH_FACT`).
- **Production** : un ordre de fabrication consomme des composants (selon `ART_NOMENC`) et fait entrer des produits finis en stock.
- **Stock** : chaque réception, consommation, production, expédition, transfert entre sites ou écart d'inventaire est un mouvement dans `STK_MVT`. Le type de mouvement et les codes de statut sont expliqués dans `PAR_CODE`.

### Les produits finis

| Code | Produit | Gamme | Prix catalogue 2025 | Usine |
|---|---|---|---|---|
| AE06 | Pompe à chaleur Aéris 6 | standard | 6 890 € | Seneffe, ligne L1 |
| AE09 | Pompe à chaleur Aéris 9 | standard | 8 450 € | Seneffe, ligne L1 |
| AE12 | Pompe à chaleur Aéris 12 | standard | 9 980 € | Seneffe, ligne L2 |
| AP16 | Pompe à chaleur Aéris Pro 16 | premium | 13 900 € | Seneffe, ligne L3 |
| AP22 | Pompe à chaleur Aéris Pro 22 | premium | 17 250 € | Seneffe, ligne L3 |
| VD30 | Groupe de ventilation Ventis D300 | standard | 3 290 € | Gand, ligne V1 |
| VD45 | Groupe de ventilation Ventis D450 | standard | 4 180 € | Gand, ligne V2 |
| VP45 | Groupe de ventilation Ventis D450 Pro | premium | 5 640 € | Gand, ligne V2 |

Les prix 2026 ont augmenté de 3,5 % (gamme standard) et 5 % (gamme premium), avec des exceptions par client.

## 2. La comptabilité (PostgreSQL)

Logiciel comptable belge, utilisé depuis le 1er janvier 2025 : les soldes de l'ancien logiciel ont été repris à cette date (journal `AN`). Plan comptable minimum normalisé belge (PCMN), comptes à six chiffres.

### Les tables

| Table | Contenu |
|---|---|
| `exercice`, `periode` | Exercices 2025 (clôturé) et 2026, périodes mensuelles avec leur statut. |
| `plan_comptable` | 78 comptes. Le premier chiffre est la classe : 1 à 5 bilan, 6 charges, 7 produits. |
| `journal` | Ventes, achats, banque, salaires, opérations diverses, à-nouveaux. |
| `tiers` | Clients et fournisseurs de la comptabilité, avec numéro de TVA et IBAN. |
| `centre_analytique` | Centres de coût par site et par service, centres de ventes par région. |
| `ecriture`, `ligne_ecriture` | Écritures (pièces) et leurs lignes au débit ou au crédit. |
| `taux_tva` | Codes TVA utilisés sur les lignes. |
| `budget` | Budget 2026 par compte et par mois. |
| `immobilisation`, `amortissement` | Registre des immobilisations et dotations mensuelles. |
| `compte_bancaire`, `mouvement_bancaire` | Extraits bancaires et leur rapprochement avec les écritures. |

### Ce qui arrive en comptabilité

- **Ventes** : les factures de l'ERP sont importées chaque nuit dans le journal `VEN`.
- **Achats** : les factures fournisseurs de l'ERP sont importées dans le journal `ACH`. Les autres factures (énergie, loyers, transport, honoraires, investissements, intérimaires...) ne passent pas par l'ERP : elles ne sont qu'en comptabilité.
- **Salaires** : le logiciel de paie produit une écriture par mois dans le journal `SAL`.
- **Banque** : les extraits bancaires sont importés (format CODA) et rapprochés des factures par lettrage.

Rappels de comptabilité utiles :

- chaque ligne a un montant au débit ou au crédit, toujours positif ; une écriture est équilibrée (total débit = total crédit) ;
- un produit (classe 7) s'inscrit au crédit, une charge (classe 6) au débit ;
- le lettrage relie une facture et son paiement : une ligne client (400000) ou fournisseur (440000) non lettrée est encore ouverte.

## 3. La paie (PostgreSQL)

Logiciel du secrétariat social, utilisé depuis juin 2025. Il calcule la paie des travailleurs belges (sièges et sites belges).

### Les tables

| Table | Contenu |
|---|---|
| `work_sites`, `departments`, `cost_centers` | Lieux de travail, départements, centres de coût. |
| `job_positions`, `salary_scales` | Fonctions (ouvriers, employés, cadres, direction) et barèmes. |
| `employees` | Travailleurs : identité, entrée, sortie, responsable. Contient des données personnelles. |
| `contracts`, `salary_history` | Contrats et avenants (une ligne par période), historique des salaires. |
| `timesheets`, `absence_types` | Prestations journalières : heures prévues et prestées, absences, télétravail, équipe. |
| `pay_elements` | Éléments de paie (salaire, primes, cotisations, retenues) et compte comptable associé. |
| `payroll_runs`, `payslips`, `payslip_lines` | Calculs de paie, fiches de paie et leurs lignes. |

Les fiches de paie existent aussi en PDF dans le dossier `fiches_paie` (7 298 fichiers). La base ne stocke que leur chemin (`payslips.pdf_path`).

### Données personnelles

Numéro national, IBAN et adresse des travailleurs sont dans `employees`. Le compte de l'agent (`agent_ro`) n'a pas accès à ces trois colonnes. Les salaires individuels restent lisibles : à votre agent de décider ce qu'il peut afficher, et à qui.

## 4. Les liens entre les sources

Il n'y a pas de clé commune propre entre les trois systèmes : ils ont été achetés à des époques différentes. Voici les liens connus. Les formats ne sont pas toujours identiques d'un côté à l'autre.

| Objet | ERP | Comptabilité | Paie |
|---|---|---|---|
| Facture client | `VTE_FACT.FAC_NUM` | `ecriture.reference_externe` (journal `VEN`) | |
| Facture fournisseur d'articles | `ACH_FACT.AF_NUM_FRN` | `ecriture.reference_externe` (journal `ACH`) | |
| Client | `CLI_CLIENT.CLI_TVA` | `tiers.numero_tva` | |
| Fournisseur, transporteur | `FRN_FOURNISSEUR.FRN_TVA`, `LOG_TRANSP.TRP_TVA` | `tiers.numero_tva` | |
| Commercial | `VDR_VENDEUR.VDR_MATRICULE` | | `employees.employee_id` |
| Compte comptable | `ART_FAMILLE.FAM_CPT_VENTE`, `ART_FAMILLE.FAM_CPT_ACHAT` | `plan_comptable.numero_compte` | `pay_elements.gl_account` |
| Centre de coût | | `centre_analytique.code_centre` | `cost_centers.gl_cost_center` |
| Site | `SOC_SITE.SIT_CODE` | `centre_analytique.site` | `work_sites.site_code` |
| Calcul de paie | | `ecriture.reference_externe` (journal `SAL`) | `payroll_runs.run_id` |

Ces liens se trouvent dans des bases différentes, sur deux moteurs différents : une jointure SQL entre l'ERP et la comptabilité est impossible sans outil de fédération. Votre agent devra interroger chaque source puis rapprocher les résultats.

## 5. Questions pour démarrer

Quelques questions avec leur réponse attendue, pour vos premiers tests. Elles ne suffisent pas comme jeu d'évaluation : complétez-les avec les vôtres.

| # | Question | Source | Réponse attendue |
|---|---|---|---|
| 1 | Quel est le chiffre d'affaires net facturé (HT) de mars 2026 ? | ERP | 13 599 646,63 € |
| 2 | Combien d'unités de produits finis Distrinergie a-t-il achetées de janvier à mai 2026 ? | ERP | 1 230 |
| 3 | Combien de vannes du lot V-2544 ont été reçues, et combien ont été retournées au fournisseur ? | ERP | 600 reçues le 19/11/2025, 386 retournées le 03/12/2025 |
| 4 | Combien de compresseurs manquaient à la livraison Kompra du 3 mars 2026, et quand sont-ils arrivés ? | ERP | 20 (une palette sur huit), reçus le 10/03/2026 |
| 5 | Quel est le résultat net de l'exercice 2025 ? | Comptabilité | 5 412 000,00 € |
| 6 | Quels sont l'EBITDA et la marge d'EBITDA de mars 2026 ? | Comptabilité | 1 278 366,78 €, soit 9,4 % |
| 7 | Combien d'amortissements ont été comptabilisés en 2025 ? | Comptabilité | 3 310 589,37 € |
| 8 | Combien de personnes sont sous contrat au 31/05/2026, par site ? | Paie | Gand 190, Herstal 6, Namur 126, Seneffe 287 |
| 9 | Combien de jours a duré l'absence pour accident du travail survenu à Gand en novembre 2025 ? | Paie | 12 jours ouvrés, du 13 au 28 novembre |
| 10 | Combien de jours de télétravail ont été prestés en avril et en mai 2026 ? | Paie | 292 en avril, 531 en mai |
| 11 | Le chiffre d'affaires de mai 2026 est-il le même dans l'ERP et en comptabilité ? | ERP et comptabilité | Non : 11 299 581,08 € dans l'ERP, 10 947 075,29 € en comptabilité |
| 12 | Quelle commission Joris Claes a-t-il reçue sur sa fiche de paie de mars 2026, et sur quelle base ? | ERP et paie | 731,38 €, soit 0,1 % de ses ventes facturées de février 2026 (731 384,61 €) |
