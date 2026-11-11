# Kafel Ventas

Plataforma para coordinar un equipo de ventas: vendedores, clientes, agenda, ventas con ticket, comisiones, pagos con comprobante, cobros, cotizador y chat. Un solo archivo (`index.html`) conectado a Supabase.

## Archivos

| Archivo | Para qué sirve |
|---|---|
| `index.html` | Toda la aplicación (vendedor y coordinador). |
| `supabase/schema.sql` | Tablas, seguridad (RLS), funciones, notificaciones, comprobantes y catálogo de ejemplo. |

## Puesta en marcha

1. **Base de datos:** Supabase → *SQL Editor* → *New query* → pega todo `supabase/schema.sql` → *Run*. Se puede volver a ejecutar sin duplicar datos.
2. **Autenticación:** *Authentication → Sign In / Providers → Email* → desactiva **Confirm email** (si no, cada cuenta nueva exige confirmar por correo y el correo gratuito de Supabase tiene límite de envíos). Para el enlace de "¿Olvidaste tu contraseña?", agrega la dirección donde publiques la app en *Authentication → URL Configuration → Redirect URLs*.
3. **Catálogo real:** el SQL carga 3 productos marcados `(EJEMPLO)`. Reemplázalos en *Table Editor → catalog* (precio base, descripción, ventajas una por línea, `seller_pct` para mensualidades). Los precios del coordinador se ajustan solos.
4. **Probar:** abre `index.html` en el navegador o súbelo a Netlify (*Add new site → Deploy manually*, arrastra la carpeta).
5. Crea primero la cuenta de **coordinador**; en su resumen verás el código de grupo para los vendedores.
6. En `index.html`, constante `KAFEL_WHATSAPP`: pon tu número con indicativo (ej. `573001234567`) para que el logo del pie de página abra tu WhatsApp.

## Qué incluye

- **Vendedor:** resumen con comisión ganada / por confirmar / disponible para cobrar, meta mensual, gráficas, agenda de seguimientos, clientes (lista y tablero; vendidos en verde, el resto en negro), registro de ventas con ticket, suscripciones, subida de comprobantes, cobros recibidos, productos con precios en vivo, cotizador imprimible y por WhatsApp, chat y notificaciones.
- **Coordinador:** código de grupo y solicitudes de ingreso con WhatsApp, ventas por vendedor, tickets con estado de entrega, suscripciones, revisión de comprobantes, precios y comisiones por producto, equipo con ranking, metas y pago de comisiones, reportes con exportación a CSV, agenda del equipo, chat grupal y privado.

## Reglas de dinero

- **Venta única:** `excedente = precio de venta − precio base`. El coordinador reparte el excedente entre vendedor (comisión) y él (utilidad), producto por producto.
- **Mensualidad:** precio fijo y 20 % para el vendedor (columna `seller_pct`), cada mes que el cliente pague. No es editable por el coordinador.
- Una comisión cuenta como **ganada** cuando el coordinador aprueba el comprobante; antes aparece como **por confirmar**. Lo que el coordinador ya pagó al vendedor se registra en *Equipo → vendedor → Registrar pago de comisión*.

## Seguridad

La clave `sb_publishable_…` es pública por diseño. La protección real son las políticas RLS: cada usuario solo ve su grupo, los precios y roles no se pueden falsificar desde el navegador y los comprobantes están en un bucket privado.

## Límites conocidos

- Cualquiera puede registrarse como coordinador (crea su propio grupo vacío). Más adelante se puede exigir un código de administrador.
- Los pagos son manuales (comprobante + aprobación). La automatización queda para una fase siguiente.
- El texto de tratamiento de datos es un borrador: revísalo con un asesor legal.
- Las notificaciones aparecen dentro de la app (campanita); no son notificaciones push del celular.
