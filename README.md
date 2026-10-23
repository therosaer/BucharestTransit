# BucharestTransit

## English

BucharestTransit is a Romanian-language iOS app for exploring public transport in Bucharest and Ilfov. It brings live vehicle positions, route information, bundled timetables, and map layers together in a native SwiftUI app.

> This is an independent project and is not affiliated with or endorsed by STB, TPBI, Metrorex, Bilet TB, or the map-data providers. Live information and timetables may be incomplete, delayed, or unavailable; check official sources when making travel decisions.

### Features

- **Live vehicle map** with route filters, vehicle details, and multiple map styles.
- **Route directory and route details** for buses, trolleybuses, trams, and metro.
- **Stop information and scheduled departures** based on bundled TPBI GTFS-derived data.
- **Map layers** for transit infrastructure and stops.
- **Vehicle-following Live Activity** on supported iOS versions.
- **YouthTB account view** for existing annual student or pupil travel titles and their QR codes. The app does not sell or activate tickets.
- **Local startup data**, allowing the map to show a bundled vehicle snapshot when live data is unavailable.

The interface is currently available in Romanian. Live vehicle data and ticket-account features require an internet connection; map tiles are provided by external services.

### Requirements

- iOS 17 or later
- Swift 6.4 or later
- [xtool](https://github.com/xtool-org/xtool) to build and run the iOS app from Linux
- A connected iPhone to install and run the app on-device

### Build and run

From the repository root:

```sh
xtool dev build
xtool dev run --usb
```

List devices recognized by xtool:

```sh
xtool devices
```

`xtool.yml` contains the bundle identifier used for the build. Replace the example identifier with one you control before signing or distributing the app. Building directly with `swift build` on Linux is not supported because the Linux Swift toolchain does not include Apple UI frameworks such as SwiftUI and WebKit.

### Data, privacy, and attribution

- Scheduled departures and route geometry are bundled with the app and derived from public transit data. Their accuracy depends on the source and update cycle.
- Live vehicle information is fetched directly from the mo-bi.ro public feed. The app uses bundled data when the live feed is unavailable.
- Location access is requested when the user asks to show their position. Coordinates are used for the map and nearby-stop context; the selected map provider receives tile requests for the visible area.
- The ticket view connects to STB's ticketing service when a user signs in to view existing YouthTB titles. Session tokens are stored in the iOS Keychain; a cached account summary is stored in app preferences. Review STB's applicable terms and privacy practices before signing in.
- Map data and styles are attributed in the app to their providers, including OpenStreetMap contributors, CARTO, and OpenTopoMap.
- Leaflet is bundled for the map interface; see its [license](https://github.com/Leaflet/Leaflet/blob/main/LICENSE).

The MIT license in this repository applies to the project's own code. Bundled datasets, third-party libraries, and externally served map data may have separate terms; review them and preserve required notices before redistribution.

### Project layout

```text
Sources/
  BucharestTransit/             iOS app, services, views, and bundled transit data
    Resources/AppIcon.png       1024x1024 app icon configured for xtool
  TransitLiveActivityShared/    Shared Live Activity model
  TransitLiveActivityWidget/    Live Activity widget extension
docs/                           Architecture and UI design notes
tools/web-prototype-and-data/   Earlier web prototype and related data
```

### Contributing

Issues and pull requests are welcome. Include the affected iOS version and reproduction steps in bug reports. For changes to transit data or map layers, include the source and applicable license or attribution requirements.

## Romanian

Aplicație iOS în limba română pentru explorarea transportului public din București și Ilfov. Reunește pozițiile live ale vehiculelor, informațiile despre linii, orarele incluse în aplicație și straturile hărții într-o aplicație nativă SwiftUI.

> Acesta este un proiect independent, neafiliat și neavizat de STB, TPBI, Metrorex, Bilet TB sau furnizorii de hărți. Informațiile live și orarele pot fi incomplete, întârziate sau indisponibile; verifică sursele oficiale înainte de a lua decizii privind călătoria.

## Funcționalități

- **Hartă cu vehicule live**, filtre pentru linii, detalii despre vehicule și mai multe stiluri de hartă.
- **Catalog de linii și detalii despre trasee** pentru autobuze, troleibuze, tramvaie și metrou.
- **Informații despre stații și plecări programate** pe baza datelor GTFS TPBI incluse în aplicație.
- **Straturi de hartă** pentru infrastructura și stațiile de transport.
- **Live Activity pentru urmărirea unui vehicul**, pe versiunile de iOS compatibile.
- **Vizualizarea contului YouthTB** pentru titlurile anuale existente pentru elevi sau studenți și codurile lor QR. Aplicația nu vinde și nu activează titluri de călătorie.
- **Date locale la pornire**, astfel încât harta poate afișa o copie inclusă a vehiculelor când datele live nu sunt disponibile.

Interfața este momentan disponibilă în limba română. Datele live despre vehicule și funcțiile contului de bilete necesită conexiune la internet; dalele hărții sunt furnizate de servicii externe.

## Cerințe

- iOS 17 sau o versiune ulterioară
- Swift 6.4 sau o versiune ulterioară
- [xtool](https://github.com/xtool-org/xtool) pentru construirea și rularea aplicației iOS din Linux
- Un iPhone conectat pentru instalarea și rularea aplicației pe dispozitiv

## Construire și rulare

Din directorul principal al depozitului:

```sh
xtool dev build
xtool dev run --usb
```

Pentru a afișa dispozitivele recunoscute de xtool:

```sh
xtool devices
```

Fișierul `xtool.yml` conține identificatorul de pachet folosit la construire. Înlocuiește identificatorul exemplu cu unul pe care îl deții înainte de semnarea sau distribuirea aplicației. Construirea directă cu `swift build` pe Linux nu este acceptată, deoarece toolchain-ul Swift pentru Linux nu include framework-uri Apple precum SwiftUI și WebKit.

## Date, confidențialitate și atribuiri

- Orarele de plecare și geometria traseelor sunt incluse în aplicație și provin din date publice de transport. Acuratețea lor depinde de sursa de date și de frecvența actualizării.
- Informațiile live despre vehicule sunt preluate direct din fluxul public mo-bi.ro. Dacă datele live nu sunt disponibile, aplicația folosește datele locale incluse.
- Accesul la locație este solicitat când utilizatorul cere afișarea poziției sale. Coordonatele sunt folosite pentru hartă și contextul stațiilor din apropiere; furnizorul selectat al hărții primește cereri pentru dalele zonei afișate.
- Secțiunea de bilete se conectează la serviciul STB când utilizatorul se autentifică pentru a vedea titlurile YouthTB existente. Tokenurile sesiunii sunt păstrate în Keychain-ul iOS; un rezumat al contului este păstrat în preferințele aplicației. Consultă termenii și practicile de confidențialitate STB înainte de autentificare.
- Datele hărții și stilurile acesteia sunt atribuite în interfață furnizorilor respectivi, inclusiv contributorilor OpenStreetMap, CARTO și OpenTopoMap.
- Leaflet este inclus pentru interfața hărții; consultă [licența](https://github.com/Leaflet/Leaflet/blob/main/LICENSE).

Licența MIT din acest depozit se aplică propriului cod al proiectului. Seturile de date incluse, bibliotecile terțe și datele hărților furnizate din exterior pot avea termeni separați; verifică acești termeni și păstrează atribuțiile necesare înainte de redistribuire.

## Structura proiectului

```text
Sources/
  BucharestTransit/             Aplicația iOS, servicii, interfețe și date de transport incluse
    Resources/AppIcon.png       Pictograma aplicației 1024x1024 configurată pentru xtool
  TransitLiveActivityShared/    Modelul comun pentru Live Activity
  TransitLiveActivityWidget/    Extensia widget pentru Live Activity
docs/                           Documentația arhitecturii și ghidul de design
tools/web-prototype-and-data/   Prototipul web anterior și date asociate
```

## Contribuții

Sunt binevenite problemele raportate și pull request-urile. Include versiunea iOS afectată și pașii de reproducere în rapoartele de bug. Pentru modificări ale datelor de transport sau straturilor hărții, indică sursa și cerințele aplicabile de licență sau atribuire.

## Licență

Codul proiectului este disponibil conform [Licenței MIT](LICENSE), cu respectarea termenilor separați pentru date și componente terțe descriși mai sus.

---

### License

Project code is available under the [MIT License](LICENSE), subject to the third-party and data terms described above.
