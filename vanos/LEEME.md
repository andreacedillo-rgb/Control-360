# Levantamiento de vanos: instalación como app (PWA)

Contenido: `index.html` (la app), `manifest.webmanifest`, `sw.js` (modo sin conexión), `icons/`, `fonts/` (IBM Plex) y `lib/` (PDF y ZIP). Nada depende de internet una vez instalada.
Suba **toda la carpeta tal cual** (sin cambiar nombres) a un hosting con HTTPS.

## 1. Publicarla (elija una, todas gratis)
- **Netlify (la más rápida):** entre a app.netlify.com/drop y arrastre esta carpeta. Entrega un enlace https al instante.
- **Cloudflare Pages:** Workers y Pages > Crear > Pages > Subida directa > arrastre la carpeta.
- **GitHub Pages:** suba los archivos a un repositorio y active Settings > Pages.
Si tiene un dominio de la empresa, puede ligarlo (por ejemplo vanos.catraar.com).

## 2. Instalarla en el iPad
1. Abra el enlace en **Safari**.
2. Compartir > **Añadir a pantalla de inicio**.
3. Ábrala una vez **con internet** para que guarde todo; desde ahí funciona sin conexión.

## 3. Google Drive (opcional)
1. console.cloud.google.com > cree un proyecto > habilite **Google Drive API**.
2. Pantalla de consentimiento OAuth > agregue los usuarios de prueba (o publíquela).
3. Credenciales > ID de cliente OAuth > **Aplicación web** > en "Orígenes autorizados de JavaScript" ponga la URL de su hosting (sin ruta final).
4. Pegue el Client ID en la app: Ajustes > Google Drive. Para elegir carpetas existentes cree también una **API Key** y péguela ahí.
La app solo pide el permiso `drive.file` (crear y subir archivos).

## 4. Actualizar la app
Cambie `index.html` y suba además el valor `VERSION` en `sw.js` (por ejemplo `vanos-v3`). Las tablets recogen la nueva versión al abrirla con internet.

## Importante
- Los levantamientos se guardan **en cada iPad**. Si borran los datos del sitio o cambian de equipo, se pierden los no exportados. Exporte o suba a Drive con frecuencia.
- DWG no se genera (formato propietario); se entrega DXF compatible con AutoCAD.
