
# Felix Card Game



<img width="1840" height="1049" alt="image" src="https://github.com/user-attachments/assets/08a37ef9-1345-42ee-a385-bd59173625f7" />

## Setup

### 1. Godot
Download [Godot 4.6](https://godotengine.org/) and open `project.godot`.

### 2. GodotSteam binaries
The Steam extension binaries are not included in the repo. Download them from [godotsteam.com](https://godotsteam.com/getting_started/introduction/) and place the following files in the **project root** (next to `project.godot`):

```
libgodotsteam.windows.template_debug.x86_64.dll
libgodotsteam.windows.template_release.x86_64.dll
steam_api64.dll
```

### 3. steam_appid.txt
Create a `steam_appid.txt` file in the project root:

```
480
```

> `480` is Valve's Spacewar test app — every Steam account owns it. Replace with your real App ID when you ship.

### 4. Steam
Steam must be running and logged in before launching the game.

## Multiplayer Testing

To test multiplayer you need **two Steam accounts**:

1. Run the game from the Godot editor (Account A — host)
2. Export the game (**Project → Export → Windows Desktop**), place `steam_appid.txt` next to the `.exe`, run it logged into Account B
3. Host clicks **Host a Room** → copies the Lobby ID shown in the top-left
4. Client pastes the Lobby ID on the **Multiplayer Menu** → clicks **Join**

You can also use the **Invite Friends** button in the room to send a Steam overlay invite directly.




## Assets Attribution (CC BY 4.0)

This project uses third-party assets licensed under **Creative Commons Attribution 4.0 International (CC BY 4.0)**.

---

### 🃏 Joker Card Image

- **Title:** Joker Card Image  
- **Author:** Wikimedia Commons contributors  
- **Source:** https://commons.wikimedia.org/wiki/File:Joker_Card_Image.jpg  
- **License:** Creative Commons Attribution 4.0 International (CC BY 4.0)  
- **License URL:** https://creativecommons.org/licenses/by/4.0/  
- **Modifications:** Used as texture for in-game playing card.

---

### 🂡 Playing Cards 3D Model

- **Title:** Playing Cards  
- **Author:** Sketchfab Creator (see model page)  
- **Source:** https://sketchfab.com/3d-models/playing-cards-793274af15df4f20848d83ab6d127493  
- **License:** Creative Commons Attribution 4.0 International (CC BY 4.0)  
- **License URL:** https://creativecommons.org/licenses/by/4.0/  
- **Modifications:** Imported into Blender and modified for gameplay usage.

---

### 🪑 Round Table and Chairs 3D Model

- **Title:** Round Table and Chairs  
- **Author:** Sketchfab Creator (see model page)  
- **Source:** https://sketchfab.com/3d-models/round-table-and-chairs-b3b1d1d338aa46ed9d480a613098e024  
- **License:** Creative Commons Attribution 4.0 International (CC BY 4.0)  
- **License URL:** https://creativecommons.org/licenses/by/4.0/  
- **Modifications:** Used as environment asset in the game.
