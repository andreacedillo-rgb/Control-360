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

## Excepciones de proveedor: las libera Compras o Administración

Ya no las autoriza Dirección. La excepción («PROVEEDOR CON EXCEPCIÓN») la autoriza o rechaza **Compras** (gastos dirigidos a Compras) o **Administración** (gastos dirigidos a Administración), en la partida o en su pestaña «Excepciones», una vez que la requisición llega a su bandeja (después de Auditoría). Mientras esté pendiente no se puede liberar a Dirección. Si la rechazan, la requisición regresa al residente. Dirección ya no tiene la pestaña ni los botones de excepción. No requiere migración.

## Altas y bajas de trabajadores (migración 007)
Nuevo apartado integrado a Nómina y a los perfiles de empleados.
- **Residente** → «Altas de personal» → SOLICITAR ALTA DE TRABAJADOR: nombre completo, obra y **seis documentos obligatorios** (Constancia de Situación Fiscal, documento con NSS, INE vigente, CURP, comprobante de domicilio, acta de nacimiento). No se puede enviar sin los seis; puede guardar borrador. Solo ve sus propias solicitudes y, si se devuelve o rechaza, corrige y reenvía.
- **Administración** → «Altas y bajas» → *Solicitudes pendientes*: Aceptar (captura el sueldo base diario; crea o vincula el perfil en Nómina), Devolver para corrección o Rechazar (justificación obligatoria). Queda registrado quién, cuándo y por qué. También puede registrar altas directas (mismos seis documentos + sueldo) y es el único perfil que registra **bajas**.
- **Dos estatus independientes**: solicitud (Borrador, Pendiente de revisión por Administración, Devuelta para corrección, Rechazada, Aceptada) y situación laboral (Pendiente de alta ante IMSS, Activo, Baja registrada). Aceptar **no** es el alta ante el IMSS: el trabajador queda «Pendiente de alta ante IMSS» hasta cargar el documento ALTA (fecha de movimiento + archivo). La BAJA cambia la situación y desactiva al empleado sin borrar historial.
- **Expediente permanente**: documentos de alta, DOCUMENTOS LABORALES (ALTA/BAJA IMSS con fecha del movimiento, fecha de carga, usuario y archivo), solicitudes, nómina e historial de movimientos.
- **Visibilidad**: Residente solo sus solicitudes; Administración todo; Dirección consulta expedientes, solicitudes e historial; Compras y Auditor sin acceso; Sistemas sin acceso a los expedientes. Las consultas de documentos laborales quedan en la bitácora de seguridad (sin nombres de trabajadores).
- **Notificaciones** a Administración (solicitud nueva o reenviada) y al residente (aceptada, rechazada, devuelta) con trabajador, folio, fecha, estado y liga directa.
- **Reportes**: «Solicitudes de alta» y «Trabajadores (situación laboral)» en el Centro de reportes (PDF/Excel, filtros por búsqueda y fechas).
- **Supabase**: ejecutar `supabase/migrations/007_altas_bajas.sql` en el SQL Editor. Crea las reglas para `altas_trabajadores` y `expedientes_trabajadores` y restringe los archivos de RH (`<uid>/rh/…`) a Dirección, Administración y quien los subió. Subir también el `js/supabase-adapter.js` actualizado.

### Solicitud de baja por el residente
El residente también puede usar **SOLICITAR BAJA DE TRABAJADOR**: elige al trabajador, la fecha propuesta y escribe la **justificación obligatoria**. Administración la acepta, devuelve o rechaza (con justificación) y el residente recibe notificación; si la devuelven o rechazan puede corregir y reenviar. Aceptar la solicitud **no da de baja** al trabajador: el expediente muestra el aviso y Administración registra después la BAJA con el documento oficial del IMSS. Las solicitudes de baja (folio BAJ-) comparten lista, notificaciones y reportes con las de alta, identificadas en la columna «Tipo». No requiere cambios en Supabase.

### Folio manual de la OC
Al generar una orden de compra, Compras captura **manualmente el folio real**: el sistema muestra el prefijo fijo «OC-» y Compras escribe el número que le asignó (ej. 1458 → OC-1458). Es obligatorio, solo admite letras, números y - _ / . y no se puede repetir un folio ya usado. Ese folio es el que aparece en Administración, Calendario, reportes y el Centro de reportes. «No aplica OC» no cambia.

### Vista «Todas» con filtros
«Todas» (todos los perfiles que la tienen) ahora trae buscador (folio, obra, solicitante, concepto, proveedor, estatus) y filtros por estatus con contador: En proceso, Por autorizar, Autorizadas, Rechazadas y Pagadas. En Dirección, «Resueltas» muestra solo lo que Dirección ya resolvió, con un resumen de autorizadas, rechazadas y pagadas.

### Expediente completo del empleado
- **«Nuevo empleado»** en Empleados ya no crea un empleado «a secas»: abre el alta directa, que exige nombre, obra, sueldo y los **seis documentos de alta**. Sin ellos no se registra. (Los datos de nómina —horas extra, vacaciones, jornada, días— se ajustan con «Editar datos de nómina».)
- **Expediente** (botón en Empleados o en Altas y bajas → Trabajadores): muestra los seis documentos de alta, los documentos laborales IMSS (ALTA/BAJA), **contratos, actas administrativas y otros documentos**, solicitudes, nómina e historial.
- **Administración** puede agregar contratos, actas administrativas, incapacidades, constancias y otros (tipo, fecha, descripción y archivo obligatorios), y es la **única que sustituye** documentación (alta, IMSS o adicionales). Toda sustitución exige motivo y conserva la versión anterior, con usuario y fecha. Los empleados anteriores al módulo pueden completar sus documentos faltantes con «Cargar».
- Dirección consulta todo, sin botones de edición. Residente, Compras, Auditor y Sistemas no acceden a los expedientes.

## Proyectos — carpetas por obra (migración 008)
Solo Administración. Sección «Obras → Proyectos»: cada proyecto se da de alta con **Nombre del proyecto, Cliente y Ubicación** y aparece como una carpeta amarilla. Al abrirla muestra sus datos, historial y la opción de editar. Ejecutar `supabase/migrations/008_proyectos.sql` en Supabase.
Contrato por proyecto: dentro de la carpeta, «Subir contrato» exige archivo, fecha de inicio, fecha de término **o** periodo de ejecución (el otro se calcula solo, en días naturales con el día de inicio incluido), monto total, % de anticipo y % de fondo de garantía (ambos montos se calculan solos y se redondean a centavos). Editar condiciones o sustituir el archivo exige motivo y conserva versiones anteriores.
Calendario y alertas de proyectos (solo Administración): el inicio y el término de cada contrato aparecen en el Calendario (verde y rojo). En cada proyecto, «Agregar alerta» permite avisar N días antes del inicio o del término, o en una fecha específica con nota. La alerta se marca en el calendario (amarillo) y llega como notificación diaria desde el día indicado hasta la fecha del evento (crítica cuando faltan 3 días o menos).
Fianzas por proyecto: «Agregar fianza» exige archivo de la póliza, afianzadora, tipo (cumplimiento, anticipo, vicios ocultos u otra), fecha de inicio, fecha de término y monto (número de póliza opcional). La lista muestra el estado (Vigente, vence en N días si faltan 30 o menos, Vencida) y el % del contrato. Inicio y vencimiento aparecen en el calendario de Administración y se puede crear una alerta N días antes del vencimiento de cada fianza. Editar o sustituir la póliza exige motivo y conserva versiones.

## Proyectos — carpetas internas, SIROC, facturación y reportes (solo Administración)
No requieren migración nueva: se guardan dentro del documento del proyecto (colección `proyectos`, migración 008). Los archivos se suben al bucket privado en la ruta `<uid>/rh/…` (visible solo para Administración, Dirección y quien lo subió).

- **Pantalla del proyecto**: datos del contrato en grande, saldos en verde, carpetas (**Fianzas, Facturas y estimaciones, Aditivas y deductivas, SIROC (IMSS)**), alertas y, al final, historial plegable.
- **Facturas y estimaciones** (PDF o Excel): tipo, folio, fecha y captura manual de **Monto neto, Anticipo amortizado y Fondo de garantía**. Los importes del contrato no cambian; los saldos («Por cobrar», «Anticipo por amortizar», «Fondo de garantía por retener») se calculan sobre el monto vigente. La factura descuenta por defecto; la estimación no (casilla editable).
- **Aditivas y deductivas**: cambian el monto total actualizado (el original se conserva); anticipo y fondo actualizados se calculan con los mismos porcentajes. **Aditiva de tiempo**: días de ampliación o nueva fecha de término; se muestran fecha original y vigente.
- **Aviso rojo «REVISAR FIANZAS / REVISAR SIROC · SE SALE DE PERIODO»**: aparece cuando la fecha de término vigente rebasa la vigencia de cualquier fianza o la terminación estimada del registro SIROC (también en el formulario antes de guardar, en la carpeta y como notificación crítica diaria).
- **SIROC (IMSS)**: registro de la obra (folio, registro patronal, fechas, acuse), avisos presentados, **pagos de seguro social** (periodo pagado desde/hasta y alerta obligatoria para revisar el siguiente periodo) y trabajadores asignados (un trabajador solo puede estar activo en una obra). Límites de registro y de aviso de terminación (plazo editable, 5 días naturales por defecto — confirmar con el asesor del IMSS) en el calendario, alertas y notificaciones.
- **Reporte PDF por proyecto** («Descargar reporte PDF»): contrato, aditivas, saldos, fianzas, facturas, SIROC, pagos IMSS, trabajadores, alertas e historial. Solo detalles (nombre del archivo, fecha, quién, montos), no los archivos.

### Borradores sin duplicados (solicitudes de alta)
Guardar un borrador y enviarlo ya no crea dos solicitudes: ambas acciones usan el mismo folio. No se permite una segunda solicitud de alta del mismo trabajador (mismo nombre) mientras haya una en borrador, pendiente o devuelta. Se bloquea el doble clic. El residente puede **Eliminar borrador** (solo borradores sin enviar; no requiere migración, se oculta del listado y queda en el historial).

### Planos y archivos CAD
Todos los campos de carga de documentos (contratos, fianzas, SIROC, facturas, aditivas, expedientes, etc.) aceptan además **DWG, DXF, DWF, DWFX, DWT, DGN, RVT, IFC y SKP** (límite 50 MB por plano; 20 MB para el resto). El bucket de Supabase no restringe tipos de archivo, no requiere migración. Si un plano pesa más de 50 MB, súbalo comprimido en ZIP o revise el límite global en Supabase → Storage → Settings.

### Calendario para Auditor
El perfil Auditor tiene la pestaña **Calendario** (solo lectura): fechas en que se requiere el material de todas las requisiciones enviadas y entregas compromiso de todas las OC de Compras, con sus tablas de próximos requerimientos y entregas. No ve los hitos de proyectos (solo Administración).

## Compras: reprogramar la fecha de llegada (con o sin OC)
- Compras ve el botón **Fecha de llegada** en cualquier partida no rechazada y no recibida por completo, **con o sin OC y con o sin paquetería**.
- Pide la nueva fecha y el **motivo** (obligatorio). Aplica solo a esa partida; conserva la fecha original, marca REPROGRAMADA y deja registro en el historial.
- Con OC se actualiza la entrega compromiso; sin OC se guarda como "Llegada programada" (por defecto, la fecha requerida de la requisición).
- El calendario (incluido el del Auditor) refleja las fechas nuevas. No requiere migración.

## Sistemas: anuncios con confirmación de enterado
- Sistemas → **Seguridad → Anuncios**: «Nuevo anuncio» con título, mensaje y destinatarios (todos, o solo algunos por perfil y/o usuarios en particular).
- El destinatario ve el anuncio **a pantalla completa, en rojo**, y no puede usar la plataforma ni cerrarlo hasta pulsar **ENTERADO**. Si hay varios, se muestran uno por uno.
- Sistemas ve cuántos confirmaron (y quién y cuándo) y quién falta; puede **retirar** un anuncio. El envío queda en la bitácora.
- **Requiere migración:** ejecutar `supabase/migrations/009_anuncios.sql` en Supabase → SQL Editor (nuevas colecciones `anuncios` y `anuncios_enterados`).

## Altas con excepción de documentos (solo Administración)
- El residente **siempre** debe cargar los seis documentos para enviar una solicitud de alta.
- **Solo Administración** puede registrar un **alta directa con documentos faltantes**: debe escribir el **motivo de la excepción**. Queda en el historial y el expediente muestra el aviso «Alta con excepción de documentos» con los pendientes, que Administración puede cargar después desde el expediente.
- No requiere migración.

## Tareas asignadas (Auditor → cualquier usuario)
- **Auditor → «Tareas (asignar)»:** crea la tarea (proyecto, tarea, notas, tiempo de ejecución, fecha de solicitud y de entrega) y la asigna a **cualquier usuario**. Ve el resumen (vencidas, vigentes, detenidas, terminadas, con solicitud), filtra por proyecto/responsable/estado y busca. Puede editar (cambios de fecha, responsable o estado piden motivo y quedan en el historial; se conserva la fecha original) y **resolver solicitudes de modificación** (aprobar o rechazar con motivo).
- **Todos los perfiles → «Tareas asignadas»:** el usuario ve sus tareas, con insignia de pendientes/vencidas. Puede **marcarla como terminada** (queda la fecha real; si es posterior a la programada aparece «Terminado en destiempo») o **solicitar una modificación** (nueva fecha y motivo) que el Auditor aprueba o rechaza.
- **Vencido / Vigente** se calculan solos con la fecha de entrega; sin fecha = «s/fecha» (vigente).
- **Dirección** tiene además «Seguimiento de tareas» (solo lectura).
- Hay notificaciones al asignar, al terminar, al solicitar modificación y al resolverla.
- **Requiere migración:** `supabase/migrations/010_tareas.sql` (colección `tareas`, y permite al Auditor leer la lista de usuarios para asignar).

### Adjuntos en tareas
- El Auditor puede adjuntar documentos al crear la tarea o después; quien recibe la tarea puede adjuntar mientras no esté terminada. Ambos ven todos los adjuntos (quién los subió y cuándo). El Auditor puede quitar cualquiera; cada usuario, los suyos. Todo queda en el historial.
- Formatos: PDF, imágenes, Word, Excel, PowerPoint, CSV, texto y planos (DWG, DXF…); 20 MB por archivo (planos 50 MB).
- Cambia `js/supabase-adapter.js` (carpeta `tareas/` en el almacenamiento): hay que subir también esa carpeta `js` a GitHub. No requiere otra migración.

### Aviso «TIENES X tareas asignadas» y «Ver como» usuario
- Al entrar, si el usuario tiene tareas sin terminar aparece un aviso grande **«TIENES X TAREAS ASIGNADAS»** (con cuántas están vencidas) y el botón **REVISAR**, que lo lleva a *Tareas → Tareas asignadas*. «Ver después» lo cierra solo por esa sesión. Si hay un anuncio de Sistemas pendiente, ese sale primero.
- El selector **«Ver como»** (visible para el propietario) ahora lista, además de los perfiles, a los **usuarios** dados de alta (p. ej. Julio Estrada) para ver exactamente lo que ve esa persona: sus tareas, avisos y anuncios dirigidos a ella. En el artefacto de prueba hay un usuario demo.
- Corrección: los anuncios dirigidos a «usuarios en particular» ahora identifican correctamente al usuario.
- No requiere migración.

### Tareas en el calendario
- Las tareas con fecha de entrega aparecen en el **Calendario** (y en «OC y entregas» de Compras): rosa = pendiente, **rojo = vencida**, verde tachada = terminada. Cada usuario ve **sus** tareas; Auditor y Dirección ven **todas**. Un clic abre el detalle y lleva a Tareas.
- Debajo del calendario, la tabla «Tareas por entregar». No requiere migración.

## Quién puede asignar tareas (restricción)
Por el momento solo pueden **crear, editar y resolver solicitudes de modificación** de tareas: el perfil **Auditor** y la cuenta **julio.estrada@catraar.com** (pestaña "Tareas (asignar)"). Todos los demás ven únicamente "Tareas asignadas" (marcar terminada, solicitar modificación, adjuntar).
- En la app: constante `TAR_ASIGNA` en `index.html`.
- En la base de datos: función `c360_asigna_tareas()` en `supabase/migrations/010_tareas.sql` (agregue ahí otros correos en minúsculas). Si ya ejecutó la 010, vuelva a ejecutarla completa; es segura de repetir.

## Eliminar tareas
Quien **crea** una tarea (Auditor o julio.estrada@catraar.com) puede eliminarla con el botón "Eliminar" (pide motivo). La tarea desaparece de las listas, del calendario y del responsable, pero **solo queda el registro**: aparece en "Registro de tareas eliminadas" (quién, cuándo, motivo), en su historial y en la Bitácora de Sistemas. No requiere migración nueva.

## Reporte PDF de tareas pendientes
En Tareas, botones **Reporte PDF por obra** y **Reporte PDF por persona**: descargan todas las tareas pendientes (no terminadas ni eliminadas), agrupadas, con folio, responsable u obra, fechas, estado actual (VENCIDO/VIGENTE) y días de atraso. Disponible para quien ve la pestaña de Tareas (Auditor, Julio y Dirección).

## Herramientas (perfil Residente)
Menú **Herramientas** solo para Residente: al elegirlo abre **directamente** la herramienta dentro de la app (con un enlace para abrirla en ventana nueva o instalarla en el iPad). Cuando haya 2 o más herramientas, el menú se despliega con una entrada por herramienta. La primera es **Levantamiento de vanos** (PWA independiente, con su propia instalación en el iPad y modo sin conexión), que vive en la carpeta **`vanos/`**.
- Suba la carpeta `vanos` completa a GitHub (junto a `index.html`), sin cambiar nombres. La app la muestra desde `vanos/index.html`.
- Las instrucciones propias de la herramienta (Google Drive opcional, instalación en iPad, actualización con `VERSION` en `vanos/sw.js`) están en `vanos/LEEME.md`.
- Para agregar más herramientas, añádalas a la lista `HERRAMIENTAS` en `index.html`.

## Levantamiento de vanos guardado en Supabase
Los levantamientos (medidas, croquis, firmas, historial) se guardan en la tabla `docs` (colección `vanos`) y las **fotografías en Storage** (bucket `comprobantes`, carpeta `<usuario>/vanos/`). Proyectos, contadores y datos de empresa van en la colección `vanos_cfg`. **Es privado por usuario**: cada persona ve, edita y elimina solamente lo que ella misma sube; nadie más (ni Dirección ni Sistemas) puede verlo. Proyectos, contadores y datos de empresa también son por usuario.
- **Sin conexión:** el iPad guarda una copia local temporal y sube lo pendiente automáticamente al volver la señal. Indicador arriba: "Supabase: N en la nube · todo sincronizado".
- **Requisitos:** ejecutar `supabase/migrations/011_vanos.sql` (después de 009 y 010) y abrir la herramienta con la sesión de CONTROL 360 iniciada (usa el mismo `config.js` de la raíz).
- Suba también `vercel.json` (ahora con `trailingSlash`, necesario para que `/vanos/` cargue sus archivos).
- La subida de PDF/ZIP a Google Drive sigue siendo opcional y aparte.

## Plan de obra · Metas SMART (Fase 1)
Menú **Plan de obra** para Residente (captura), Auditor y Dirección (consulta; Dirección además autoriza o devuelve).
- Metas SMART por proyecto y por **cualquier periodo** (no están ligadas a una semana; el periodo de una meta puede ser de un día hasta un año). Filtro de periodo: este mes, esta semana, próximos 30 días, todo el plan o fechas personalizadas.
- Metas SMART por proyecto, con redacción SMART automática, distribución diaria, validación de viabilidad (9 puntos), avance diario con evidencia, indicadores y semáforo (verde ≥100 %, amarillo ≥90 %, rojo menos; configurable por Dirección).
- Flujo: Borrador → Pendiente de autorización → Autorizado → En ejecución. Vistas: tablero y calendario semanal.
- Requisito: ejecutar `supabase/migrations/012_plan_obra.sql` (después de 009–011). Fotos de evidencia en Storage (carpeta `plan/`).
- Vistas: Resumen → Calendario → Tablero (todo filtra por proyecto, residente, periodo y buscador de obra). Reporte **PDF** completo con fichas por meta y fotos (hasta 10 fotos por día).
- **Meta incumplida:** si vence el periodo con piezas pendientes, el Residente recibe la alerta y debe reprogramar con nueva fecha, justificación y "¿Qué se hará diferente para cumplirla?". Se conserva lo ejecutado, se redistribuye lo pendiente, se avisa a Dirección y Auditor y queda en el historial.
- Fases siguientes: impedimentos y cierre semanal; control de cambios y notificaciones; tablero de Dirección con reportes PDF/Excel.

- **Programa de obra (PDF por obra):** botón en Plan de obra; diagrama Gantt por días de una sola obra (barra del día de inicio al día de término, ejecutado sombreado, línea de HOY, secuencia de ejecución). Lo generan Dirección, Auditores, el Líder de Proyectos y el residente de sus propias obras.
- **Líder de Proyectos:** julio.estrada@catraar.com ve las metas de todas las obras (lista `PLAN_LIDERES` en index.html y correo en `012_plan_obra.sql`). Los demás residentes solo ven lo que ellos suben.

## Otros cambios en esta versión
- **Alta ante el IMSS:** al cargarla Administración, el residente que solicitó el alta recibe aviso y ve el acuse en su solicitud.
- **Requisiciones de Compras:** Compras puede levantar requisiciones; pasan por Auditor y este las libera a Dirección. Excepciones de proveedor las autoriza Dirección.
- Los errores de carga de archivos ahora muestran el motivo de Supabase.
- **Sistemas · Eliminar registros:** ahora también elimina Plan de obra (metas), tareas asignadas, altas y bajas, anuncios y obras/proyectos (confirmación escribiendo ELIMINAR; queda en bitácora). Requiere volver a ejecutar `012_plan_obra.sql`.

## Requisiciones de Auditores
El Auditor tiene pestañas «Mis requisiciones» y «Nueva requisición» (Clave, Descripción, Acabado, Medida, Proveedor, Concepto(s) destino y Porcentaje de pedido; si es menor a 100% exige justificación). Va directo a Compras (cotiza, modifica, devuelve al Auditor) y Compras la libera a Dirección. Re-ejecute `supabase/migrations/012_plan_obra.sql`.

## Nota de esta entrega
Esta versión **no incluye el perfil «Proyectos»** (análisis de proyectos, Configurador, reportes PDF/Excel y dashboard de costos); se entregará aparte. Sigue vigente `012_plan_obra.sql` (Plan de obra), que debe ejecutarse en el MISMO proyecto de Supabase que usa Vercel, después de 009–011.
