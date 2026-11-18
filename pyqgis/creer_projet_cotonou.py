"""
Construit le projet QGIS « Cotonou - risques et équipements » prêt pour Lizmap.

- 12 couches PostGIS lues par le service PostgreSQL SERVICE (aucun hôte ni mot de passe
  dans le projet), un fond OpenStreetMap dans le groupe « baselayers » reconnu par Lizmap ;
- styles, alias de champs en français, champs techniques masqués (formulaire + popups WMS) ;
- projet en EPSG:3857, publication WMS/WFS, emprise annoncée, projet « de confiance » ;
- vignette PNG pour la page d'accueil de Lizmap.

Utilisation :
  - console Python de QGIS : exec(open(r"...\\pyqgis\\creer_projet_cotonou.py", encoding="utf8").read())
  - ou via le MCP QGIS (outil execute_code) avec le même contenu.
Le projet est construit dans une instance QgsProject séparée : le projet ouvert n'est pas touché.
Ensuite : Projet > Ouvrir SORTIE, puis configurer Lizmap (pyqgis/configurer_lizmap.py).

Testé avec QGIS 3.34 (Desktop) et 3.44 (Server).
"""
import os

from qgis.core import (
    Qgis, QgsCategorizedSymbolRenderer, QgsCoordinateReferenceSystem, QgsCoordinateTransform,
    QgsEditorWidgetSetup, QgsGraduatedSymbolRenderer, QgsMapRendererParallelJob, QgsMapSettings,
    QgsPalLayerSettings, QgsProject, QgsRasterLayer, QgsRectangle, QgsRendererCategory,
    QgsRendererRange, QgsRuleBasedRenderer, QgsSingleSymbolRenderer, QgsSymbol,
    QgsTextBufferSettings, QgsTextFormat, QgsVectorLayer, QgsVectorLayerSimpleLabeling, QgsWkbTypes,
)
from qgis.PyQt.QtCore import QSize, Qt
from qgis.PyQt.QtGui import QColor, QFont

# --------------------------------------------------------------------------- paramètres
SERVICE = "cotonou_db"                      # nom du service PostgreSQL (identique des deux côtés)
SRID = 32631                                # SCR des tables
SORTIE = r"D:\lizmap\lizmap\instances\cotonou\cotonou.qgs"
TITRE = "Cotonou - risques et équipements"
RESUME = ("Carte de Cotonou : zones inondables, équipements publics (éducation, santé, sécurité), "
          "littoral, îlots de chaleur, espaces verts et densité de population 2025, sur fond "
          "OpenStreetMap. Données : base PostGIS cotonou_db.")
MOTS_CLES = ["Cotonou", "inondation", "équipements", "littoral", "chaleur", "espaces verts", "population"]

WEB = QgsCoordinateReferenceSystem("EPSG:3857")
projet = QgsProject()


# --------------------------------------------------------------------------- outils
def couche(schema, table, nom, type_geom):
    """Couche PostGIS par service. key/srid/type évitent des requêtes au chargement."""
    uri = (f"service='{SERVICE}' key='gid' estimatedmetadata=true checkPrimaryKeyUnicity='1' "
           f"srid={SRID} type={type_geom} table=\"{schema}\".\"{table}\" (geom)")
    lyr = QgsVectorLayer(uri, nom, "postgres")
    if not lyr.isValid():
        raise RuntimeError(f"Couche invalide : {schema}.{table} (service {SERVICE} déclaré ?)")
    # Pas de simplification côté base : le plugin Lizmap le demande
    methode = lyr.simplifyMethod()
    methode.setForceLocalOptimization(True)
    lyr.setSimplifyMethod(methode)
    projet.addMapLayer(lyr, False)
    return lyr


def surface(couleur, opacite, contour, epaisseur=0.2, vide=False):
    s = QgsSymbol.defaultSymbol(QgsWkbTypes.PolygonGeometry)
    c = QColor(couleur)
    c.setAlphaF(opacite)
    s.symbolLayer(0).setFillColor(c)
    s.symbolLayer(0).setStrokeColor(QColor(contour))
    s.symbolLayer(0).setStrokeWidth(epaisseur)
    if vide:
        s.symbolLayer(0).setBrushStyle(Qt.NoBrush)
    return s


def ligne(couleur, epaisseur):
    s = QgsSymbol.defaultSymbol(QgsWkbTypes.LineGeometry)
    s.setColor(QColor(couleur))
    s.setWidth(epaisseur)
    return s


def point(couleur, taille=2.6):
    s = QgsSymbol.defaultSymbol(QgsWkbTypes.PointGeometry)
    s.setColor(QColor(couleur))
    s.setSize(taille)
    s.symbolLayer(0).setStrokeColor(QColor("white"))
    s.symbolLayer(0).setStrokeWidth(0.3)
    return s


def champs(lyr, alias, masques):
    """Alias français ; champs techniques cachés du formulaire ET des popups (GetFeatureInfo)."""
    for nom, texte in alias.items():
        i = lyr.fields().indexOf(nom)
        if i >= 0:
            lyr.setFieldAlias(i, texte)
    for nom in masques:
        i = lyr.fields().indexOf(nom)
        if i >= 0:
            lyr.setEditorWidgetSetup(i, QgsEditorWidgetSetup("Hidden", {}))
            lyr.setFieldConfigurationFlag(i, Qgis.FieldConfigurationFlag.HideFromWms, True)


# --------------------------------------------------------------------------- couches
commune = couche("referentiel", "limite_communale", "Limite communale", "Polygon")
commune.setRenderer(QgsSingleSymbolRenderer(surface("#000000", 0, "#222222", 0.8, vide=True)))
champs(commune, {"nom": "Commune", "superficie_km2": "Superficie (km²)"}, ["gid", "source"])

arr = couche("referentiel", "arrondissements", "Arrondissements", "MultiPolygon")
s = surface("#000000", 0, "#555555", 0.4, vide=True)
s.symbolLayer(0).setStrokeStyle(Qt.DashLine)
arr.setRenderer(QgsSingleSymbolRenderer(s))
etiq = QgsPalLayerSettings()
etiq.fieldName = "nom"
fmt = QgsTextFormat()
fmt.setFont(QFont("Arial"))
fmt.setSize(9)
fmt.setColor(QColor("#333333"))
tampon = QgsTextBufferSettings()
tampon.setEnabled(True)
tampon.setSize(0.8)
tampon.setColor(QColor("white"))
fmt.setBuffer(tampon)
etiq.setFormat(fmt)
arr.setLabeling(QgsVectorLayerSimpleLabeling(etiq))
arr.setLabelsEnabled(True)
champs(arr, {"nom": "Arrondissement", "superficie_km2": "Superficie (km²)", "pop_2013": "Population 2013",
             "densite_2013": "Densité 2013 (hab/km²)"},
       ["gid", "num", "osm_id", "ajout_km2", "source", "source_pop"])

equip = couche("equipements", "equipements", "Équipements", "Point")
equip.setRenderer(QgsCategorizedSymbolRenderer("theme", [
    QgsRendererCategory("éducation", point("#f28e2b"), "Éducation"),
    QgsRendererCategory("santé", point("#d62728"), "Santé"),
    QgsRendererCategory("sécurité et services", point("#7b4ea3"), "Sécurité et services"),
]))
champs(equip, {"nom": "Nom", "nom_connu": "Nom usuel", "theme": "Thème", "categorie": "Catégorie",
               "secteur": "Secteur", "quartier_proche": "Quartier", "arrondissement": "Arrondissement (n°)",
               "confiance": "Fiabilité"},
       ["gid", "id_equipement", "autres_noms", "secteur_source", "sources", "nb_sources",
        "position_source", "code_quartier", "remarque", "a_verifier"])

inond = couche("inondations", "zones", "Zones inondables", "Polygon")
inond.setRenderer(QgsCategorizedSymbolRenderer("exposition", [
    QgsRendererCategory("forte", surface("#08519c", 0.65, "#08306b"), "Exposition forte"),
    QgsRendererCategory("probable", surface("#6baed6", 0.55, "#2171b5"), "Exposition probable"),
]))
champs(inond, {"exposition": "Exposition", "score": "Score", "surface_ha": "Surface (ha)",
               "batiments": "Bâtiments exposés", "arrondissement": "Arrondissement (n°)"}, ["gid"])

surf = couche("littoral", "surfaces", "Surfaces gagnées / perdues (1986-2026)", "MultiPolygon")
surf.setRenderer(QgsCategorizedSymbolRenderer("nature", [
    QgsRendererCategory("gagné sur la mer", surface("#35978f", 0.65, "#01665e", 0.3), "Gagné sur la mer"),
    QgsRendererCategory("perdu", surface("#8c510a", 0.7, "#543005", 0.3), "Perdu (érosion)"),
]))
champs(surf, {"nature": "Nature", "periode": "Période", "section": "Section du littoral",
              "arrondissement": "Arrondissement (n°)", "surface_ha": "Surface (ha)"}, ["gid"])

trans = couche("littoral", "transects", "Évolution du trait de côte (transects)", "LineString")
categories = [QgsRendererCategory(v, ligne(c, w), t) for v, c, w, t in [
    ("recul rapide (plus de 3 m/an)", "#b2182b", 0.9, "Recul rapide (> 3 m/an)"),
    ("recul (1 à 3 m/an)", "#ef8a62", 0.7, "Recul (1 à 3 m/an)"),
    ("stable (moins de 1 m/an)", "#9e9e9e", 0.6, "Stable (< 1 m/an)"),
    ("avancée (1 à 3 m/an)", "#67a9cf", 0.7, "Avancée (1 à 3 m/an)"),
    ("avancée rapide (plus de 3 m/an)", "#2166ac", 0.9, "Avancée rapide (> 3 m/an)"),
]]
categories.append(QgsRendererCategory(None, ligne("#d9d9d9", 0.4), "Non calculé"))
trans.setRenderer(QgsCategorizedSymbolRenderer("tendance", categories))
champs(trans, {"id_transect": "Transect", "section": "Section du littoral", "arrondissement": "Arrondissement (n°)",
               "mesures": "Nombre de mesures", "evolution_nette_m": "Évolution nette (m)",
               "vitesse_m_an": "Vitesse (m/an)", "vitesse_ic95_m_an": "IC 95 % (m/an)", "r2": "R²",
               "vitesse_avant_2015_m_an": "Vitesse avant 2015 (m/an)", "saut_2018_2020_m": "Saut 2018-2020 (m)",
               "vitesse_depuis_2020_m_an": "Vitesse depuis 2020 (m/an)",
               "vitesse_depuis_2020_ic95": "IC 95 % depuis 2020 (m/an)", "tendance": "Tendance"}, ["gid"])

riv = couche("littoral", "rivages", "Traits de côte 1984-2026", "MultiLineString")
riv.setRenderer(QgsGraduatedSymbolRenderer("annee", [
    QgsRendererRange(a, b, ligne(c, 0.5), f"{a} – {b}") for a, b, c in [
        (1984, 1990, "#fde725"), (1990, 2005, "#7ad151"), (2005, 2015, "#22a884"),
        (2015, 2020, "#2a788e"), (2020, 2024, "#414487"), (2024, 2026, "#440154")]
]))
champs(riv, {"date": "Date", "annee": "Année", "satellite": "Satellite", "resolution_m": "Résolution (m)",
             "transects_mesures": "Transects mesurés"}, ["gid", "image"])

ilots = couche("chaleur", "ilots", "Îlots de chaleur", "Polygon")
ilots.setRenderer(QgsCategorizedSymbolRenderer("classe", [
    QgsRendererCategory("îlot de chaleur", surface("#fd8d3c", 0.65, "#e6550d", 0.3), "Îlot de chaleur"),
    QgsRendererCategory("îlot de chaleur intense", surface("#bd0026", 0.75, "#800026", 0.4), "Îlot de chaleur intense"),
]))
champs(ilots, {"lieu": "Lieu", "quartier": "Quartier", "arrondissement": "Arrondissement (n°)", "classe": "Classe",
               "occupation": "Occupation du sol", "surface_ha": "Surface (ha)", "ecart_moyen_c": "Écart moyen (°C)",
               "ecart_max_c": "Écart maximal (°C)", "temperature_sol_c": "Température du sol (°C)",
               "part_batie_pct": "Part bâtie (%)", "batiments": "Bâtiments", "habitants_2025": "Habitants 2025",
               "ecart_1987_c": "Écart en 1987 (°C)", "situation_1987": "Situation en 1987"}, ["gid", "id_ilot"])

ev = couche("vegetation", "espaces_verts", "Espaces verts", "MultiPolygon")
ev.setRenderer(QgsSingleSymbolRenderer(surface("#41ab5d", 0.6, "#238b45")))
champs(ev, {"nom": "Nom", "categorie": "Catégorie", "acces": "Accès", "surface_ha": "Surface (ha)",
            "part_vegetalisee_pct": "Part végétalisée (%)", "arrondissement": "Arrondissement (n°)"}, ["gid", "id_osm"])

hexa = couche("population", "hexagones", "Densité de population 2025 (hab/km²)", "Polygon")
bornes = [18, 3063, 6293, 9881, 14007, 46927]     # quintiles de densite_2025
teintes = ["#ffffb2", "#fecc5c", "#fd8d3c", "#f03b20", "#bd0026"]
hexa.setRenderer(QgsGraduatedSymbolRenderer("densite_2025", [
    QgsRendererRange(bornes[i], bornes[i + 1], surface(teintes[i], 0.7, "#ffffff", 0.05),
                     f"{bornes[i]:,} – {bornes[i + 1]:,}".replace(",", " ")) for i in range(5)
]))
champs(hexa, {"pop_2013": "Population 2013", "pop_2025": "Population 2025", "terre_km2": "Surface terrestre (km²)",
              "densite_2025": "Densité 2025 (hab/km²)"}, ["gid", "id_hexagone"])

voirie = couche("fond", "voirie", "Voirie", "MultiLineString")
racine_regles = QgsRuleBasedRenderer.Rule(None)
for libelle, expr, couleur, ep in [
    ("Voies principales", "\"highway\" IN ('trunk','trunk_link','primary','primary_link')", "#e15759", 0.9),
    ("Voies secondaires", "\"highway\" IN ('secondary','secondary_link','tertiary','tertiary_link')", "#f1a340", 0.6),
    ("Autres voies", None, "#9e9e9e", 0.25),
]:
    regle = QgsRuleBasedRenderer.Rule(ligne(couleur, ep), 0, 0, expr or "", libelle)
    if expr is None:
        regle.setIsElse(True)
    racine_regles.appendChild(regle)
voirie.setRenderer(QgsRuleBasedRenderer(racine_regles))
champs(voirie, {"name": "Nom", "highway": "Type de voie"}, ["gid", "osm_id"])

eau = couche("fond", "cours_eau", "Cours d'eau", "MultiLineString")
eau.setRenderer(QgsSingleSymbolRenderer(ligne("#3a8fd9", 0.5)))
champs(eau, {"name": "Nom", "waterway": "Type"}, ["gid", "osm_id"])

osm = QgsRasterLayer("type=xyz&url=https://tile.openstreetmap.org/{z}/{x}/{y}.png&zmax=19&zmin=0",
                     "OpenStreetMap", "wms")
projet.addMapLayer(osm, False)

# --------------------------------------------------------------------------- arbre des couches
# Règles Lizmap : un groupe ne doit pas porter le même nom qu'une couche ;
# le groupe « baselayers » à la racine devient la liste des fonds de carte.
racine = projet.layerTreeRoot()


def groupe(nom, couches, masquees=()):
    g = racine.addGroup(nom)
    for lyr in couches:
        noeud = g.addLayer(lyr)
        noeud.setItemVisibilityChecked(lyr not in masquees)
    return g


groupe("Référentiel", [commune, arr])
groupe("Équipements publics", [equip])
groupe("Risques", [inond])
groupe("Littoral", [surf, trans, riv], masquees=[riv])
groupe("Chaleur urbaine", [ilots])
groupe("Environnement", [ev, hexa], masquees=[hexa])
groupe("Fond de plan", [voirie, eau])
groupe("baselayers", [osm]).setExpanded(False)

# --------------------------------------------------------------------------- projet et services OGC
# Le SCR se fixe APRÈS l'ajout des couches : QGIS adopte sinon celui de la première couche.
projet.setCrs(WEB)
projet.setTitle(TITRE)
projet.setTrustLayerMetadata(True)

emprise = QgsCoordinateTransform(commune.crs(), WEB, projet).transformBoundingBox(commune.extent())
emprise.grow(max(emprise.width(), emprise.height()) * 0.08)

projet.writeEntry("WMSServiceCapabilities", "/", True)
projet.writeEntry("WMSServiceTitle", "/", TITRE)
projet.writeEntry("WMSServiceAbstract", "/", RESUME)
projet.writeEntry("WMSKeywordList", "/", MOTS_CLES)
projet.writeEntry("WMSExtent", "/", [f"{v:.2f}" for v in (emprise.xMinimum(), emprise.yMinimum(),
                                                            emprise.xMaximum(), emprise.yMaximum())])
projet.writeEntry("WMSUseLayerIDs", "/", False)
projet.writeEntry("WMSAddWktGeometry", "/", True)
projet.writeEntry("WMSFeatureInfoUseAttributeFormSettings", "/", True)
vecteurs = [commune, arr, equip, inond, surf, trans, riv, ilots, ev, hexa, voirie, eau]
projet.writeEntry("WFSLayers", "/", [lyr.id() for lyr in vecteurs])
for lyr in vecteurs:
    projet.writeEntry("WFSLayersPrecision", "/" + lyr.id(), 6)

os.makedirs(os.path.dirname(SORTIE), exist_ok=True)
if not projet.write(SORTIE):
    raise RuntimeError(f"Écriture impossible : {SORTIE}")

# --------------------------------------------------------------------------- vignette Lizmap
visibles = [lyr for lyr in racine.layerOrder() if racine.findLayer(lyr.id()).isVisible()]
centre = emprise.center()
h = emprise.height() * 0.62
w = h * 4 / 3
reglages = QgsMapSettings()
reglages.setLayers(visibles)
reglages.setDestinationCrs(WEB)
reglages.setExtent(QgsRectangle(centre.x() - w / 2, centre.y() - h / 2, centre.x() + w / 2, centre.y() + h / 2))
reglages.setOutputSize(QSize(400, 300))
reglages.setBackgroundColor(QColor("white"))
rendu = QgsMapRendererParallelJob(reglages)
rendu.start()
rendu.waitForFinished()
rendu.renderedImage().save(SORTIE + ".png", "PNG")

print(f"Projet écrit : {SORTIE}")
print(f"{len(vecteurs)} couches PostGIS + OpenStreetMap - SCR {projet.crs().authid()}")
for lyr in vecteurs:
    # estimatedmetadata=true : nombre lu dans les statistiques PostgreSQL (-1 tant qu'ANALYZE n'a pas tourné)
    n = lyr.featureCount()
    print(f"  {lyr.name():45s} {n if n >= 0 else '?':>7} entités")
