# CONTROL 360

Plataforma administrativa (requisiciones, compras, proveedores, nómina, reportes, usuarios y permisos) para Grupo Catraar.
Frontend estático (HTML/JS, sin build) + **Supabase** (base de datos, autenticación, archivos, tiempo real) + despliegue en **Vercel** desde **GitHub**.

```
index.html                 aplicación
config.js                  URL y anon key de Supabase (editar)
js/supabase-adapter.js     conecta la app con Supabase (login, base de datos, archivos)
supabase/schema.sql        tablas, seguridad RLS, triggers, bucket de archivos
supabase/functions/gestionar-usuario/index.ts   crea usuarios y restablece contraseñas (sin correos)
vercel.json                configuración de Vercel
```

## 1. Supabase (≈15 min)
1. Cree un proyecto en https://supabase.com (región cercana, p. ej. us-east / Mexico si está disponible). Guarde la contraseña de la base.
2. **SQL Editor → New query**: abra `supabase/schema.sql`, **cambie `CAMBIE@SUCORREO.COM` por su correo** (será el primer usuario con perfil SISTEMAS), pegue todo y pulse *Run*.
3. **Authentication → Users → Add user → Create new user**: ese mismo correo, una contraseña segura y marque *Auto Confirm User*.
4. **Project Settings → API**: copie *Project URL* y *anon public key* → péguelos en `config.js`.
5. **Authentication → URL Configuration**: *Site URL* = la URL de Vercel (paso 3); agregue la misma en *Redirect URLs*. (Para pruebas locales agregue también `http://localhost:3000`.)
6. **Authentication → Providers → Email**: deje activo y **desactive** *Allow new users to sign up* (solo Sistemas da de alta usuarios). No necesita configurar correo: la plataforma no envía emails.
7. (Opcional) *Authentication → Policies*: contraseña mínima de 10 caracteres.
8. **Edge Function** (crear usuarios y restablecer contraseñas). Con la CLI de Supabase (`npm i -g supabase`):
   ```
   supabase login
   supabase link --project-ref SU_PROJECT_REF
   supabase functions deploy gestionar-usuario
   ```
   (También puede pegarla desde el panel: *Edge Functions → Deploy a new function*.)

## 2. GitHub
```
git init
git add .
git commit -m "CONTROL 360"
git branch -M main
git remote add origin https://github.com/SU_ORG/control-360.git
git push -u origin main
```
Use un repositorio **privado**. (La anon key es pública por diseño; la seguridad la dan las políticas RLS. **Nunca** suba la `service_role key`.)

## 3. Vercel
1. https://vercel.com → *Add New → Project* → importe el repositorio de GitHub.
2. *Framework Preset*: **Other**. Sin comando de build, *Output Directory* vacío (raíz).
3. *Deploy*. Copie la URL (o conecte su dominio) y úsela en el paso 1.5 de Supabase.
Cada `git push` a `main` publica automáticamente.

## 4. Primer uso
1. Abra la URL e ingrese con el correo/contraseña del paso 1.3 (perfil SISTEMAS).
2. **Usuarios y permisos → Nuevo usuario**: nombre, correo (es su usuario) y perfil. El sistema genera una contraseña temporal y se la muestra **una sola vez** a Sistemas para entregarla a la persona. En su primer ingreso la plataforma le obliga a crear su contraseña personal. Si alguien la olvida: *Restablecer acceso* genera otra temporal y cierra sus sesiones.
3. Cada usuario entra directo a su entorno. Cambios de perfil o desactivación se aplican de inmediato y quedan en la **Bitácora de seguridad**.

## Seguridad aplicada (a nivel de base de datos, RLS)
- SISTEMAS solo accede a usuarios y bitácora; no lee requisiciones, compras, proveedores, nóminas, pagos ni reportes.
- RESIDENTE solo lee y escribe sus propias requisiciones y nóminas; sus comprobantes están en su carpeta.
- Usuario desactivado o no registrado: la base le niega todo.
- Nadie puede cambiar su propio perfil/estado/correo; correo único; solo Compras puede eliminar proveedores sin movimientos; nada más se borra (historial íntegro).
- Contraseñas gestionadas por Supabase Auth (cifradas); la temporal no se guarda y se obliga a cambiarla en el primer ingreso.

## Notas
- Los comprobantes se sirven con enlaces firmados de 1 año; quien tenga el enlace puede abrirlo. Para mayor control reduzca la vigencia en `js/supabase-adapter.js`.
- Si `config.js` conserva los valores de ejemplo, la app corre en **modo local** (demo, sin compartir datos).
- Datos existentes del artefacto en Claude **no se migran** automáticamente; esta instalación inicia vacía.
- Respalde: Supabase → Database → Backups (plan Pro tiene respaldos diarios).

## Documentos adjuntos y Centro de Notificaciones (migración 004)
**Instalaciones existentes:** ejecute UNA VEZ `supabase/migrations/004_documentos_notificaciones.sql` en Supabase → SQL Editor, y luego suba `index.html` (nunca `config.js`).
- **Documentos**: Compras, Administración y el residente (solo en sus requisiciones) adjuntan en cualquier estado; Dirección consulta y descarga; Sistemas no los ve. Una sustitución crea una versión nueva y conserva las anteriores. No se pueden modificar ni borrar.
- **Notificaciones** (campana 🔔 + pestaña *Avisos → Notificaciones*): por perfil, con prioridad, módulo, leído/no leído y enlace directo solo si el usuario tiene acceso. Sistemas únicamente recibe avisos de seguridad/usuarios. Las notificaciones no se modifican ni se borran (evidencia); solo cambia su estado de lectura, que es por usuario.
- Alertas de "pendiente de autorizar", "sin OC", "por recibir" y "pagos por programar" se calculan en vivo cada día.
- Limitaciones: las notificaciones las genera la sesión que realiza la acción; no hay avisos por fecha de vencimiento de pago ni por intentos fallidos de contraseña (eso lo registra Supabase Auth, no la app); los documentos de una requisición eliminada por Sistemas quedan huérfanos en el almacenamiento.

## Reposiciones (migración 005)
**Instalaciones existentes:** ejecute UNA VEZ `supabase/migrations/005_reposiciones.sql` y luego suba `index.html` (nunca `config.js`).
- Pestaña **Reposiciones** (Residente, Compras, Administración, Dirección). Residente y Administración registran; la solicitud exige comprobante, folio e importe del comprobante coincidente, confirmación de legibilidad y justificación detallada. Si falta algo queda **Incompleta** y no puede enviarse.
- Flujos: Residente → Compras → Dirección; Residente → Administración → Dirección; Administración → Dirección (registro directo). Dirección autoriza (puede autorizar un importe menor), rechaza o solicita aclaración.
- Autorizada: aparece en **Por pagar** de Administración como “REPOSICIÓN A COLABORADOR”; se programa el pago y se marca Pagada adjuntando el comprobante de transferencia.
- Vinculación con requisición: las partidas seleccionadas quedan “cubiertas por el colaborador” y salen de Por pagar al proveedor; si la reposición se rechaza, el vínculo se libera. Alertas de posible duplicado (folio de comprobante, importe/fecha/proveedor, concepto/obra, pagos existentes al proveedor).
- El residente solo ve sus reposiciones (política de base de datos). Notificaciones integradas. Reportes PDF/Excel en **Reportes → Reporte de reposiciones**, con exactamente los registros filtrados; cada descarga queda en el registro de descargas.
- Limitación: la detección de duplicados compara contra lo que el usuario puede ver (un residente solo detecta contra sus propias reposiciones; Compras/Administración/Dirección, contra las de su alcance).

## Material en bodega
En el campo Proveedor de cada partida (alta o edición) puede elegirse **MATERIAL EN BODEGA**: no requiere proveedor; sigue el flujo de revisión y autorización de Dirección, pero no genera OC, recepción ni pago, y no cuenta como pendiente de compra.

## Perfil AUDITOR (migración 006)

Nuevo flujo para requisiciones dirigidas a **Compras**: Residente → **Auditor** → Compras → Dirección.

- El Auditor **solo valida** conceptos, cantidades y justificación. No cotiza ni edita partidas, ni ve datos bancarios de proveedores.
- Puede **liberar a Compras**, **devolver al residente** (con justificación), **rechazar partidas específicas** (motivo obligatorio, reversible con «Deshacer» mientras la requisición siga en su bandeja) o **rechazar toda la requisición** (se cierra sin pasar a Compras).
- Los gastos dirigidos a **Administración** y las **Reposiciones** no pasan por Auditoría.
- Si Compras o Dirección devuelven una requisición, al corregirla el residente vuelve a pasar por Auditoría.
- Las partidas rechazadas por Auditoría llegan a Compras/Dirección ya marcadas como rechazadas (con motivo).

**Para activarlo en Supabase:** ejecute `supabase/migrations/006_auditor.sql` en el SQL Editor (requiere 004 y 005 ya ejecutadas). Después cree usuarios con perfil «Auditor» desde Sistemas → Usuarios y permisos. Suba `index.html` a GitHub **sin** `config.js`.

## Costo de paquetería (ESTIMADO)

- Compras puede agregar, al editar una partida en su bandeja, un **costo de paquetería** opcional rotulado «ESTIMADO»; se suma al total que autoriza Dirección.
- Ya autorizado el gasto, Compras solo puede modificar ese costo (botón «Paquetería», antes de generar la OC).
- Si el nuevo costo supera lo autorizado por **más de $1,000**, la partida regresa automáticamente a **Administración** (para revisión y liberación a Dirección, que debe reautorizarla). Si no, el ajuste se libera y queda autorizado.
- No requiere migración de Supabase.

## Auditoría numérica (revisión previa a publicar)

- Todas las sumas ahora se redondean a 6 decimales internos (se elimina el ruido de punto flotante) y se muestran a centavos.
- Una partida ya autorizada ya no puede ser editada por Residente, Compras ni Administración (solo partidas pendientes); la única excepción es el costo de paquetería por Compras.
- Los reportes ya no cuentan como «saldo» el material en bodega ni las partidas cubiertas por reposición.
- Los campos numéricos ya no cambian al girar la rueda del ratón sobre ellos.

## Observaciones del Auditor por partida

El Auditor puede dejar una **observación** en cualquier partida pendiente («Observar») sin rechazarla. Al devolver la requisición, el residente ve la justificación general y, en el aviso y en cada partida, las observaciones y los motivos de rechazo de Auditoría. Se limpian al reenviar (quedan en el historial).

## Centro de reportes (PDF y Excel)

En la pestaña **Reportes** de cada perfil: elija el tipo (Requisiciones, Partidas, Órdenes de compra, Pagos y crédito, Nóminas, Nómina por empleado, Reposiciones, Proveedores, Empleados), busque o filtre por fechas, marque registros específicos o use «todo lo mostrado», y descargue PDF o Excel. «Todo completo» genera un Excel con una hoja por tipo, o un PDF con todo. Requisiciones y OC también tienen «documento completo» (una hoja por documento). Cada perfil solo obtiene lo que ya puede consultar (Residente: lo suyo y sin importes de nómina; Proveedores solo Compras/Administración/Dirección; Empleados solo Administración; Nómina solo Residente/Administración/Dirección). Cada descarga queda en el registro de reportes. No requiere migración.
