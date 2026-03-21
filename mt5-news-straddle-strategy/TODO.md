# TODO — News Straddle EA

## Pending Fixes

### 1. TP en órdenes pendientes (Stop Orders)
- Cuando `InpUseTP = true`, el TP debe ser visible en las órdenes pendientes (Buy Stop / Sell Stop)
- Actualmente las órdenes se colocan con `SL=0, TP=0` y el TP solo se calcula después de que se activa la posición
- **Fix:** Pasar el TP calculado directamente al broker en `PlaceStraddleOrders()` para que sea visible en el chart y en la pestaña de órdenes de MT5

### 2. Las órdenes pendientes no se ven en el chart
- Las órdenes Buy Stop y Sell Stop se colocan pero no se visualizan claramente en el gráfico
- Agregar líneas horizontales o indicadores visuales que muestren dónde están las órdenes pendientes y el TP

---

## Backlog
- [ ] Buffer de breakeven hardcodeado (5000 pips) → hacerlo input configurable
- [ ] SL inicial en las órdenes para protección si el EA se desconecta
- [ ] Versión del UI dice v1.10, EA dice v1.12 → sincronizar
- [ ] Validación del formato de `InpNewsTime`
- [ ] Cancelación automática de órdenes pendientes si no se activan en X tiempo
- [ ] Modo trailing independiente del TP virtual

