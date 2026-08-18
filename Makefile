FLUTTER_BIN=/home/sirz/development/flutter/bin/flutter
APP_DIR=.
EXIT_DIR=exit
APK_NAME=App_Wing.apk

.PHONY: all apk chrome chrome-dev clean

# Par défaut, affiche l'aide
all:
	@echo "Commandes disponibles :"
	@echo "  make apk        : Compile l'APK en mode release et le copie dans le dossier exit/"
	@echo "  make chrome     : Lance l'application sur Google Chrome en mode debug"
	@echo "  make chrome-dev : Lance l'application sur Chrome en mode DEV"
	@echo "  make clean      : Nettoie le cache de compilation Flutter"

# Compile l'APK et le déplace dans le dossier exit
apk:
	@echo "Compilation de l'APK en cours..."
	cd $(APP_DIR) && $(FLUTTER_BIN) build apk --release
	@echo "Copie de l'APK vers le dossier $(EXIT_DIR)..."
	mkdir -p $(EXIT_DIR)
	cp $(APP_DIR)/build/app/outputs/flutter-apk/app-release.apk $(EXIT_DIR)/$(APK_NAME)
	@echo "Terminé ! L'APK se trouve dans $(EXIT_DIR)/$(APK_NAME)"

# Lance l'application sur Chrome
chrome:
	@echo "Lancement sur Chrome..."
	cd $(APP_DIR) && $(FLUTTER_BIN) run -d chrome

# Lance l'application sur Chrome en mode DEV
chrome-dev:
	@echo "Lancement sur Chrome (Mode DEV)..."
	cd $(APP_DIR) && $(FLUTTER_BIN) run -d chrome --dart-define=DEV_MODE=true

# Nettoie le cache Flutter
clean:
	@echo "Nettoyage du cache Flutter..."
	cd $(APP_DIR) && $(FLUTTER_BIN) clean
