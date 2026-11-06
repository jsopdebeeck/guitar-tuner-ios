# Tuner — app iOS (SwiftUI)

Projet Xcode prêt à ouvrir. Version 1.1.1. iOS 17+, iPhone, portrait. Aucune dépendance externe.
Interface en anglais. Nom affiché sur l'écran d'accueil : **Tuner**. Bundle ID : `be.opdebeeck.GuitarTuner`.

## Prérequis
- Mac avec **Xcode 16.3 ou plus récent** (App Store, gratuit).
- Un Apple ID (gratuit suffit) ajouté dans Xcode › Settings › Accounts.
- iPhone + câble USB-C/Lightning.

## Installation sur l'iPhone (≈ 5 min la première fois)
1. Double-cliquer `GuitarTuner.xcodeproj`.
2. Dans le navigateur de gauche : clic sur le projet **GuitarTuner** › cible **GuitarTuner** › onglet **Signing & Capabilities** › **Team** : choisir ton Apple ID (« Personal Team »).
   - Si Xcode signale que le Bundle ID est déjà pris : le modifier (ex. `be.opdebeeck.Tuner2`).
3. Brancher l'iPhone, le déverrouiller, accepter « Faire confiance à cet ordinateur ».
4. iPhone : Réglages › Confidentialité et sécurité › **Mode développeur** › activer (redémarrage requis).
5. Dans la barre du haut de Xcode, choisir l'iPhone comme destination, puis **⌘R** (Run).
6. Premier lancement avec un compte gratuit : iPhone › Réglages › Général › **VPN et gestion de l'appareil** › ton Apple ID › **Faire confiance**. Relancer l'app.
7. Accepter l'accès au micro.

## Durée de validité
| Compte | Validité de l'installation | Distribution |
|---|---|---|
| Apple ID gratuit | 7 jours, puis re-Run depuis Xcode | Tes appareils uniquement (max. 3) |
| Apple Developer Program (99 $/an) | 1 an | TestFlight, App Store |

## Structure
```
GuitarTuner.xcodeproj/        projet (groupe synchronisé : tout fichier ajouté dans GuitarTuner/ est compilé)
GuitarTuner/
  TunerApp.swift              point d'entrée
  ContentView.swift           UI : note, Hz/cents, cordes, menu accordage + diapason
  GaugeView.swift             cadran ±50 ¢ : bande colorée, zone verte, aiguille, trace qui remonte
  TunerModel.swift            état, permission micro, lissage médian, choix de corde, trace
  PitchDetector.swift         AVAudioEngine (.measurement) + YIN vectorisé vDSP
  Tunings.swift               Standard, Drop D, DADGAD, Open D, Open G
  Assets.xcassets             icône, couleur d'accent
```

## Paramètres réglables
- Seuil de silence : `rmsGate` (PitchDetector.swift).
- Tolérance « juste » et largeur de la zone verte : `TunerModel.tolerance` (3 cents).
- Vitesse de remontée de la trace : `Dial.riseSpeed` (GaugeView.swift).
- Plage détectée : 60–1200 Hz (`YIN.minFrequency` / `maxFrequency`).

## Historique des versions
| Version | Date | Objet |
|---|---|---|
| 1.1.1 | 06/11/2026 | Le micro redémarre seul après une interruption (appel, Siri, alarme), un changement de configuration audio ou une réinitialisation des services audio. |
| 1.1 | 06/11/2026 | Interface en anglais, nom affiché « Tuner ». Cadran redessiné : bande colorée vert → jaune → orange → rouge, zone verte ±3 ¢ matérialisée sur l'arc et prolongée en colonne, graduations tous les 5 ¢, ♭/♯ aux extrémités. Trace des mesures qui naît à la pointe de l'aiguille et remonte. Aiguille fluide (interpolation entre deux mesures). |
| 1.0 | 16/10/2026 | Version initiale. |
