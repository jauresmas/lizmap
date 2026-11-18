# 6. Ajouter des couches à un projet publié

[Sommaire](../README.md) · Précédent : [5. Configurer Lizmap](05-configurer-lizmap.md) · Suivant : [7. Dépannage](07-depannage.md)

Exemple réel : la première version du projet avait 8 couches. On a ajouté ensuite les **îlots de
chaleur** et trois couches sur le **littoral**.

| Groupe ajouté | Couche | Table |
|---|---|---|
| Littoral | Surfaces gagnées / perdues (1986-2026) | `littoral.surfaces` |
| | Évolution du trait de côte (transects) | `littoral.transects` |
| | Traits de côte 1984-2026 (décochée) | `littoral.rivages` |
| Chaleur urbaine | Îlots de chaleur | `chaleur.ilots` |

## 1. Vérifier que Lizmap peut lire les tables

Le rôle `lizmap` n'a de droits que sur les tables qui existaient lors de la publication de la base.
Pour des tables créées depuis :

```powershell
.\scripts\publier-base.ps1 -Base cotonou_db      # relance les GRANT, ne duplique rien
```

## 2. Ajouter et styler les couches dans QGIS

Comme au [chapitre 4](04-projet-qgis.md) : connexion **par service**, alias, champs techniques en
*Masquer dans WMS*, un groupe dont le nom diffère de celui des couches.

En PyQGIS, pour une couche :

```python
from qgis.core import QgsProject, QgsVectorLayer
uri = ("service='cotonou_db' key='gid' estimatedmetadata=true srid=32631 type=Polygon "
       "table=\"chaleur\".\"ilots\" (geom)")
ilots = QgsVectorLayer(uri, "Îlots de chaleur", "postgres")
assert ilots.isValid()
QgsProject.instance().addMapLayer(ilots, False)
QgsProject.instance().layerTreeRoot().addGroup("Chaleur urbaine").addLayer(ilots)
```

Le reste (styles, alias) est dans [`creer_projet_cotonou.py`](../pyqgis/creer_projet_cotonou.py),
qui contient déjà ces quatre couches.

### Couleurs : éviter les confusions

Le premier jet utilisait du rouge à la fois pour l'**érosion** du littoral et pour les **îlots de
chaleur intenses**. Sur la carte, impossible de les distinguer. Choix final :

| Thème | Couleurs |
|---|---|
| chaleur | orange `#fd8d3c` → bordeaux `#bd0026` |
| littoral : perdu / gagné | brun `#8c510a` / vert d'eau `#35978f` (palette divergente brun-vert) |
| inondation | bleus |
| transects : recul → avancée | rouge `#b2182b` → bleu `#2166ac`, gris si stable |

Règle simple : une famille de couleurs par thème, et les rouges réservés à un seul danger visible à
la fois (les transects sont des lignes fines, ils ne se confondent pas avec les surfaces).

## 3. Mettre à jour la configuration Lizmap

Rouvrir le plugin Lizmap : il relit le `.cfg` existant et signale les nouvelles couches.

- *Couches* : popup *auto* + résumé sur les quatre nouvelles couches ;
- *Table d'attributaire & sélection* : ajouter « Îlots de chaleur » et « Évolution du trait de côte » ;
- *Contrôles* : les nouvelles couches ont de nouveau la simplification côté fournisseur (réglage par
  défaut de QGIS) et pas d'`estimatedmetadata` : relancer les deux corrections ;
- *Appliquer*.

Le script [`configurer_lizmap.py`](../pyqgis/configurer_lizmap.py) contient déjà la configuration
finale (9 popups, 6 tables) : le relancer suffit.

## 4. Vérifier

Recharger http://localhost:8090/index.php/view/map?repository=cotonou&project=cotonou :

- les groupes *Littoral* et *Chaleur urbaine* apparaissent dans la légende ;
- un clic sur un îlot : lieu, quartier, classe, écart de température, situation en 1987 ;
- *Données* : les tables « Îlots de chaleur » et « Évolution du trait de côte (transects) ».

Suivant : [7. Dépannage](07-depannage.md)
