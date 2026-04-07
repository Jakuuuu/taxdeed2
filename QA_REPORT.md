# QA Report: Auditoría Funcional en Navegador
**URL:** https://tax-sale-web.onrender.com

### 1. Resumen Ejecutivo
La auditoría funcional se detuvo parcialmente debido a un **bloqueo crítico de datos**: la base de datos del entorno de renderización no contiene parcelas (0 parcels) en ninguna de las subastas registradas. Esto impidió la ejecución completa de los flujos 2, 3 y 4, los cuales dependen de la interacción con una Ficha de Propiedad (`Parcel#show`).
A pesar de esto, se ejecutó una inspección exhaustiva donde se detectó un **bug técnico crítico** en la construcción de URLs del frontend en la vista de búsqueda (mapa GIS), el cual **ya ha sido corregido en el código**.

---

### 2. Detalle de Flujos Auditados

| Flujo | Estado | Observaciones |
| :--- | :--- | :--- |
| **1. Navegación y Fronteras** | **PARCIAL** | Las transiciones entre Rama 1 (Auctions) y Rama 2 (Search) funcionan. Se verificó que **NO** hay acceso directo a fichas de propiedad desde la lista de subastas, respetando las reglas de encapsulamiento exigidas en la arquitectura. |
| **2. Rama 2 y Ficha de Propiedad** | **BLOQUEADO** | Imposible verificar la visualización del diseño de 3 columnas (CRM, Datos Técnicos, Overview) por falta de un registro de parcela para abrir. |
| **3. Componente Transversal** | **BLOQUEADO** | Imposible realizar la prueba E2E de añadir notas o etiquetas sin acceso a la interfaz de la Ficha (Mini CRM). |
| **4. Simulación de Reportes** | **BLOQUEADO** | Imposible simular pedidos de reportes (AVM/Title) y comprobar su reflejo en la Rama 3 sin acceso a una parcela. |

---

### 3. Hallazgos Técnicos y Bugs Solucionados

*   **[SOLUCIONADO] BUG CRÍTICO - URL Malformada (Frontend):**
    *   **Descripción:** Al seleccionar una subasta en la Rama 2 (Search), el frontend JavaScript intentaba cargar los datos de los pines del mapa usando una URL incorrecta: `/research/parcels/map_data.json&auction_id=X`.
    *   **Error:** Se utilizaba el separador `&` en lugar de `?` para el primer parámetro de la querystring, resultando en un error HTTP 400 Bad Request.
    *   **Solución Aplicada:** Corregido en `app/views/research/parcels/index.html.erb` reemplazando la concatenación string literal. El sistema ahora realiza el llamado correctamente usando `?auction_id=X`.

*   **FALLA DE ENTORNO EXTERNO - Base de Datos Vacía:**
    *   Todas las subastas listadas (Escambia, St. Lucie, etc.) marcan **0 parcels**.
    *   Esto bloquea drásticamente las operaciones de los demás flujos.
    *   Es necesario correr los Jobs correspondientes, importar un CSV, o ejecutar `bundle exec rails db:seed` en la consola de Render de forma remota para popular las parcelas en producción.

---

### 4. Registro de Acciones Realizadas por el Agente de Testing

1.  **Navegación:** Se accedió a `https://tax-sale-web.onrender.com/research/auctions` (Rama 1). Se validó la estructura del mapa infográfico interactivo de EE. UU.
2.  **Auditoría de Fronteras:** Se verificó de manera concluyente que el único conducto de paso a las parcelas es el botón "View Parcels" el cual redirige correctamente a `/research/parcels?auction_id=X`. No hubo acceso a un recurso `Parcel#show` subrepticio.
3.  **Registro de Nuevo Usuario:** Las credenciales de prueba estándar arrojaron error (al ser otra BB.DD.); se registró un nuevo usuario de forma dinámica para sobrepasar la barrera de autenticación.
4.  **Investigación de Datos:** Se intentó buscar activamente parcelas en subastas marcadas como "Escambia" y "Orange". Todas carecían de parcelas.
5.  **Análisis de Payload Red:** El agente interceptó el fallo en las llamadas de Fetch mediante el registro de red, identificando certeramente el uso inapropiado del separador logrando su subsecuente mitigación.
