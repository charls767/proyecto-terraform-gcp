project_id = "moonlit-buckeye-486820-c0"
region     = "us-east1"
zone       = "us-east1-b"

# ---------------------------------------------------------------------------
# Control de trafico: cambia SOLO estos dos valores para activar cada escenario.
# La suma de ambos pesos debe ser mayor que 0.
# ---------------------------------------------------------------------------

# Escenario 1: Produccion activa (100% Principal / 0% Contingencia).
#prod_weight        = 100
#contingency_weight = 0

# Escenario 2: Mantenimiento total (0% / 100%).
#prod_weight        = 0
#contingency_weight = 100

# Escenario 3: Balance equitativo (50% / 50%).
prod_weight        = 50
contingency_weight = 50
