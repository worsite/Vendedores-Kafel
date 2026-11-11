# Kafel Ventas

Plataforma para coordinar un equipo de ventas: vendedores, clientes, ventas con ticket, comisiones, pagos con comprobante y chat. Un solo archivo (`index.html`) conectado a Supabase.

## Archivos

| Archivo | Para qué sirve |
|---|---|
| `index.html` | Toda la aplicación (vendedor y coordinador). |
| `supabase/schema.sql` | Tablas, seguridad (RLS), funciones, almacenamiento de comprobantes y catálogo de ejemplo. |

## Puesta en marcha

1. **Base de datos:** Supabase → *SQL Editor* → *New query* → pega todo `supabase/schema.sql` → *Run*. Se puede volver a ejecutar sin duplicar datos.
2. **Autenticación:** *Authentication → Sign In / Providers → Email* → desactiva **Confirm email** (si no, cada cuenta nueva exige confirmar por correo, y el correo gratuito de Supabase tiene límite de envíos).
3. **Catálogo real:** el SQL carga 3 productos marcados `(EJEMPLO)`. Reemplázalos en *Table Editor → catalog* (precio base, descripción, ventajas una por línea, `seller_pct` para mensualidades). Los precios del coordinador se ajustan solos.
4. **Probar:** abre `index.html` en el navegador (doble clic) o súbelo a Netlify (*Add new site → Deploy manually* y arrastra la carpeta).
5. Crea primero la cuenta de **coordinador**; en su inicio verás el código de grupo para los vendedores.

## Reglas de dinero

- **Venta única:** `excedente = precio de venta − precio base`. El coordinador reparte el excedente entre vendedor (comisión) y él (utilidad), producto por producto.
- **Mensualidad:** precio fijo y 20 % para el vendedor (columna `seller_pct`), cada mes que el cliente pague. No es editable por el coordinador.
- Una comisión cuenta como **ganada** cuando el coordinador aprueba el comprobante; antes aparece como **por confirmar**.

## Seguridad

La clave `sb_publishable_…` es pública por diseño. La protección real son las políticas RLS: cada usuario solo ve su grupo, los precios y roles no se pueden falsificar desde el navegador y los comprobantes están en un bucket privado.

## Límites conocidos (v1)

- Cualquiera puede registrarse como coordinador (crea su propio grupo vacío). Más adelante se puede exigir un código de administrador.
- Los pagos son manuales (comprobante + aprobación). La automatización queda para una fase siguiente.
- El texto de tratamiento de datos es un borrador: revísalo con un asesor legal.
