---
name: version updater
description: met à jour la version du software en y glissant un nouvelle apk via ADB
tools: Bash, Read, Write
---


### 1.1 Vérifier si le casque est connecté 

''' bash
#fait un listing des appareil connectés 
adb devices

vérifier si un nom est detecté exemple : PA7Q50MGJ4280142W

si il n'y en a pas explique à l'utilisateur que aucun appareil n'est connecté à l'heure actuelle 


'''


### 1.2 Localiser et identifier l'APK 

'''bash 

#installer le fichier apk

adb install -r -d $APK_FILE_PATH 

'''

Une fois l'appareil detecté. C'est le moment de charger le fichier APK dans le casque. Tous les fichiers se trouve dans le fichier 
/APK/TEST ou /APK/PROD, une fois que tu es dedans demande explicitement quelle fichier apk veut t'il utiliser d'abord si c'est un APK test ou prod, et ensuite la version concerné.

