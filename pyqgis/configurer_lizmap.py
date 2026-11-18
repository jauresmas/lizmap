"""
Remplit le plugin Lizmap (QGIS Desktop) pour le projet Cotonou et génère cotonou.qgs.cfg.

Ce script fait, sans clic, ce que décrit docs/05-configurer-lizmap.md :
options de carte, couches (visibilité, popups, résumés), tables attributaires,
« Localiser par couche », corrections demandées par le plugin, puis enregistrement du .cfg.

Prérequis :
  1. le projet est ouvert dans QGIS (pyqgis/creer_projet_cotonou.py puis Projet > Ouvrir) ;
  2. dans le plugin Lizmap, panneau « Information », http://localhost:8090/ est déclaré avec
     le compte admin (le plugin refuse de produire le .cfg sans serveur authentifié).

Utilisation : console Python de QGIS
  exec(open(r"...\\pyqgis\\configurer_lizmap.py", encoding="utf8").read())
La fenêtre Lizmap s'ouvre, se remplit puis enregistre le .cfg ; le résultat s'affiche dans la console.

Attention : le script utilise l'intérieur du plugin (attributs de la fenêtre, gestionnaires
de tables), pas une API publique. Testé avec QGIS 3.34.12 et le plugin Lizmap 5.0.4 ;
une autre version du plugin peut renommer ces éléments.
"""
import builtins

from qgis.core import Qgis, QgsCoordinateReferenceSystem, QgsProject, QgsRectangle, QgsSettings
from qgis.PyQt.QtCore import QTimer
from qgis.utils import plugins

# --------------------------------------------------------------------------- réglages
ECHELLE_MIN, ECHELLE_MAX = 1000, 250000

# Couches avec popup (source « auto » : respecte les alias et les champs masqués du projet) + résumé
POPUPS = {
    "Arrondissements": None,
    "Équipements": "Établissements d'éducation, de santé, de sécurité et de services publics.",
    "Zones inondables": "Zones exposées aux inondations, avec le nombre de bâtiments concernés.",
    "Surfaces gagnées / perdues (1986-2026)": "Surfaces gagnées sur la mer ou perdues par érosion entre 1986 et 2026.",
    "Évolution du trait de côte (transects)": "Vitesse d'évolution du trait de côte mesurée le long de 131 transects (m/an).",
    "Traits de côte 1984-2026": "Traits de côte extraits d'images Landsat et Sentinel-2, de 1984 à 2026.",
    "Îlots de chaleur": "Îlots où la température du sol dépasse nettement la moyenne de la ville (écart en °C, situation en 1987).",
    "Espaces verts": "Parcs, zones humides, friches, cultures urbaines et autres espaces végétalisés.",
    "Densité de population 2025 (hab/km²)": "Estimation 2025 par maille hexagonale.",
}

# Tables attributaires, dans l'ordre d'affichage
TABLES = ["Équipements", "Zones inondables", "Îlots de chaleur",
          "Évolution du trait de côte (transects)", "Espaces verts", "Arrondissements"]

# Localiser par couche
LOCALISER = [
    ("Arrondissements", {"fieldName": "nom", "displayGeom": True, "minLength": 0, "filterOnLocate": False}),
    ("Équipements", {"fieldName": "nom", "filterFieldName": "theme", "displayGeom": False, "minLength": 2,
                     "filterOnLocate": False}),
]

# --------------------------------------------------------------------------- outils
liz = plugins["lizmap"]
projet = QgsProject.instance()
builtins.lizmap_resultat = "en cours"


def couche(nom):
    trouvees = projet.mapLayersByName(nom)
    if not trouvees:
        raise RuntimeError(f"Couche absente du projet ouvert : {nom}")
    return trouvees[0]


def champs_masques(lyr):
    """Champs cachés des popups dans le projet = colonnes cachées des tables attributaires."""
    return ",".join(f.name() for f in lyr.fields()
                    if f.configurationFlags() & Qgis.FieldConfigurationFlag.HideFromWms)


def avec_ordre(entrees):
    return {nom: dict(valeurs, order=i) for i, (nom, valeurs) in enumerate(entrees)}


def configurer(essai=0):
    d = liz.dlg
    if not d.isVisible():                       # la fenêtre n'est pas encore ouverte
        if essai < 20:
            QTimer.singleShot(500, lambda: configurer(essai + 1))
        return
    try:
        # Mode « Normal » : le mode « Débutant » impose toutes les mesures de protection
        # (dont l'interdiction des services PostgreSQL) et empêche d'enregistrer ce projet.
        d.radio_normal.setChecked(True)

        # ---- Options de carte
        d.use_native_scales.setChecked(True)
        d.minimum_scale.setValue(ECHELLE_MIN)
        d.maximum_scale.setValue(ECHELLE_MAX)
        d.cbActivateZoomHistory.setChecked(True)
        d.cbActivateMeasure.setChecked(True)
        d.activate_drawing_tools.setChecked(True)
        d.automatic_permalink.setChecked(True)
        d.liExternalSearch.setCurrentIndex(d.liExternalSearch.findData("nominatim"))
        d.checkbox_group_popup_by_layer.setChecked(True)
        web = QgsCoordinateReferenceSystem("EPSG:3857")
        emprise = QgsRectangle(*[float(v) for v in projet.readListEntry("WMSExtent", "/")[0]])
        d.widget_initial_extent.setOutputCrs(web)
        d.widget_initial_extent.setOutputExtentFromUser(emprise, web)

        # ---- Couches : visibilité au démarrage = celle de QGIS, popups, résumés
        racine = projet.layerTreeRoot()
        for cle, v in liz.layerList.items():
            if v["type"] == "group":
                v["toggled"] = True
                continue
            noeud = racine.findLayer(cle)
            v["toggled"] = bool(noeud and noeud.itemVisibilityChecked())
            if v["name"] in POPUPS:
                v["popup"] = True
                v["popupSource"] = "auto"
                if POPUPS[v["name"]]:
                    v["abstract"] = POPUPS[v["name"]]

        # ---- Tables attributaires
        tables = liz.layers_table["attributeLayers"]["manager"]
        tables.truncate()
        tables.from_json(avec_ordre([
            (nom, {"layerId": couche(nom).id(), "primaryKey": "gid", "hiddenFields": champs_masques(couche(nom)),
                   "export_enabled": True, "pivot": False, "hideAsChild": False, "hideLayer": False})
            for nom in TABLES]))

        # ---- Localiser par couche
        localiser = liz.layers_table["locateByLayer"]["manager"]
        localiser.truncate()
        localiser.from_json(avec_ordre([(nom, dict(r, layerId=couche(nom).id())) for nom, r in LOCALISER]))

        # ---- Corrections proposées par le plugin (panneau « Outils d'auto-correction »)
        d.fix_project_estimated_md()            # estimatedmetadata=true sur les couches PostgreSQL
        d.fix_simplify_geom_provider()          # pas de simplification côté base (bloquant)
        d.fix_project_trust()                   # projet « de confiance » (ouverture plus rapide)
        projet.write()

        # ---- Enregistrement du .cfg (le plugin enregistre aussi le projet)
        ok = liz.save_cfg_file()
        builtins.lizmap_resultat = ok
        print("cotonou.qgs.cfg enregistré" if ok else
              "Échec : voir le panneau « Contrôles » de la fenêtre Lizmap")
        print(f"  popups : {sum(1 for v in liz.layerList.values() if v.get('popup'))}"
              f" | tables : {tables.table.rowCount()} | localiser : {localiser.table.rowCount()}")
    except Exception:
        import traceback
        builtins.lizmap_resultat = "ERREUR " + traceback.format_exc()
        print(builtins.lizmap_resultat)


# --------------------------------------------------------------------------- lancement
if not liz.server_manager.check_admin_login_provided():
    raise RuntimeError("Déclarer d'abord le serveur Lizmap avec le compte admin (plugin Lizmap > Information).")

# Le projet utilise des services PostgreSQL : lever cette mesure de protection du plugin
# (« Prévenir les couches PostgreSQL d'utiliser un fichier de service »).
QgsSettings().setValue("lizmap/prevent_pg_service", False)
liz.dlg.safe_pg_service.setChecked(False)

# Fenêtre déjà ouverte : la fermer pour qu'elle relise le projet à la réouverture.
if liz.dlg.isVisible():
    liz.dlg.reject()

# La fenêtre est modale : on l'ouvre via la boucle d'événements, puis on la remplit.
QTimer.singleShot(300, liz.run)
QTimer.singleShot(2000, configurer)
print("Ouverture du plugin Lizmap...")
