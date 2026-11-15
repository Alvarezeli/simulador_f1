# Simulador de Fórmula 1: contexto del proyecto

Proyecto de la materia Informática 2: una base de datos relacional que sostiene un juego, más una aplicación jugable. **Lo que se evalúa es el modelo de datos y que las reglas del juego vivan en la base.** La aplicación es secundaria: *"una app vistosa sobre un modelo pobre no aprueba; un juego simple sobre un modelo sólido, sí"*.

El equipo es de 3 integrantes, todos aprendiendo. **El código tiene que ser simple, comentado y de nivel junior.** Ante dos soluciones, elegir siempre la más simple y legible. La defensa es individual: cada integrante tiene que poder explicar cualquier parte del código.

---

## 1. Regla principal: pedir permiso antes de cambiar algo

- **Nunca crear, modificar ni borrar archivos sin permiso explícito.** Antes de cada cambio: explicar qué se va a hacer, en qué archivo, por qué, y mostrar el cambio propuesto. Esperar un "sí" del usuario.
- Lo mismo antes de **ejecutar comandos** que instalen paquetes, modifiquen la base de datos, borren datos o hagan commits / push.
- Proponer los cambios **de a uno o en grupos chicos**, para que el equipo pueda revisarlos y entenderlos.
- Si hay varias formas de resolver algo, presentar las opciones con sus ventajas y desventajas y dejar que el usuario elija.
- Si un pedido contradice las reglas de este archivo o de la cátedra, **avisarlo antes** de hacer cualquier cosa.
- Al terminar un cambio, resumir en 2 o 3 líneas qué se hizo, para que el equipo lo anote en la bitácora de IA.

---

## 2. Reglas de la cátedra que hay que respetar

1. **No modificar el esquema de la base** (`sql/simulador_f1.sql`): ni tablas, ni columnas, ni restricciones. Si el modelo no alcanza para algo, avisar en lugar de cambiarlo. La consigna dice: *"si el modelo no alcanza, vuelvan y arreglen el modelo"*, y eso lo decide el equipo.
2. **Las reglas del juego viven en la base, no en Python.** La app llama a los procedimientos y a las vistas y muestra lo que devuelven. No validar el saldo, no calcular tiempos, posiciones ni puntos en Python. El Hito 4 controla *"que la aplicación use la base para las reglas del juego y no las duplique en el código"*.
3. **El script SQL tiene que correr limpio sobre una base vacía.** Cualquier cambio en el script (por ejemplo, agregar un procedimiento) se prueba importándolo desde cero.
4. **El juego tiene que poder jugarse de principio a fin** (las 4 carreras) con el script del Hito 3 sin cambios sustanciales.
5. **La instalación tiene que funcionar siguiendo el README** en una máquina limpia. Si se agrega una dependencia o un paso, actualizar el README.

---

## 3. Seguridad

### Credenciales y ambientes
- **Las credenciales de la base nunca se escriben en el código.** APP.py las lee de variables de entorno: `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`.
- Si se usa un archivo `.env`, **tiene que estar en `.gitignore`** y nunca subirse al repositorio. Dejar un `.env.example` con los nombres de las variables y valores ficticios.
- No imprimir contraseñas ni credenciales en la consola, en mensajes ni en logs.
- No usar el usuario `root` de la base fuera del entorno local de desarrollo.
- No subir al repositorio dumps de la base con datos reales ni archivos de configuración personales.

### Código
- **Consultas siempre parametrizadas** con `%s` de mysql-connector. Nunca armar SQL concatenando o usando f-strings con datos que vengan del usuario (evita inyección SQL).
- **Contraseñas:** se guardan con `SHA2(clave, 256)` y se comparan en la consulta. Nunca guardarlas ni mostrarlas en texto plano.
- **Cada usuario solo accede a su propia partida.** El `id_partida` sale de `st.session_state` después del login, nunca de un selector o de un dato que el usuario pueda elegir.
- **No mostrar errores internos al usuario** (mensajes de MySQL, rutas, tracebacks). El detalle va a la consola con `print`; al usuario se le muestra un mensaje simple.
- Validar los datos de los formularios (campos vacíos, largo mínimo de contraseña) antes de llamar a la base. Esto es validación de entrada, no de reglas del juego.

---

## 4. Buenas prácticas

- Código y comentarios **en español**, con nombres descriptivos y coherentes con la base.
- Funciones cortas que hagan una sola cosa, con un docstring breve.
- Toda operación que modifique más de una tabla va en **una transacción** (COMMIT si todo sale bien, ROLLBACK si algo falla), o mejor, en un procedimiento de la base.
- Abrir y cerrar la conexión en cada operación (`try / finally: conn.close()`).
- No repetir código: si algo se usa en dos lugares, extraerlo a una función.
- Separación dentro de APP.py: arriba las funciones que hablan con la base; abajo, en `main()`, solo la interfaz.
- No agregar dependencias nuevas sin permiso. Las actuales son `streamlit`, `mysql-connector-python`, `pandas` y `python-dotenv`.
- Después de cada cambio, indicar cómo probarlo a mano (qué usuario usar y qué pasos seguir).

---

## 5. Entorno

- **Base:** MariaDB 10.4 (XAMPP / phpMyAdmin). Requiere MariaDB 10.2+ o MySQL 8.0.16+ por los CHECK y `RANK() OVER`.
- **App:** Python 3.11+ con Streamlit (es la versión con la que se probó la app).
- **Instalar la base:** borrar `simulador_f1` en phpMyAdmin e importar `sql/simulador_f1.sql`. Verificar en la pestaña Rutinas que existan los 2 procedimientos.
- **Ejecutar:** `pip install -r requirements.txt` y luego `streamlit run APP.py` (abre `http://localhost:8501`).
- **Pendiente con el docente:** la consigna nombra Flask o FastAPI para Python. Hay que confirmar que acepte Streamlit.

```
simulador_f1/
├── APP.py               ← aplicación Streamlit (acceso a la base arriba, interfaz en main())
├── CLAUDE.md
├── README.md
├── .env.example         ← nombres de las variables, sin datos reales
├── .gitignore           ← incluye .env
├── .streamlit/
│   └── config.toml      ← colores y tema (opcional)
└── sql/
    └── simulador_f1.sql ← script completo del Hito 3
```

---

## 6. El juego

- Cada usuario se registra, elige una escudería y tiene **una sola partida**, con el presupuesto inicial de la temporada (50.000.000).
- La escudería elegida arranca sin pilotos y **reemplaza** a la de la semilla: sus pilotos y tiempos precargados no corren en esa partida.
- El usuario contrata **2 pilotos libres** (los que tienen `id_escuderia` NULL).
- Antes de cada carrera puede comprar **componentes**, que restan segundos y duran una cantidad limitada de carreras (`durabilidad`).
- Las **4 carreras se corren de a una y en orden**. Los rivales ya tienen sus tiempos cargados (`id_partida` NULL en RESULTADO).
- **Fórmula del tiempo** (en `sp_correr_carrera`): `tiempo_base − habilidad × 0,05 − componentes activos + azar (0 a 1,5)`. Los rivales tienen un segundo fijo de ventaja.
- La partida termina al correr la carrera 4. Los usuarios se comparan en un ranking por puntos.
- "Reiniciar temporada" borra resultados, compras y contratos de la partida y devuelve el presupuesto inicial.

---

## 7. Modelo y dónde se impone cada regla

| Tabla | Para qué sirve |
|---|---|
| usuario | Cuentas (`nombre_usuario` UNIQUE, `contrasena` = hash SHA2) |
| temporada | Calendario común y `presupuesto_inicial` |
| escuderia | Catálogo de escuderías |
| partida | El juego de un usuario: `presupuesto` (saldo actual), `estado` (0 en curso, 1 finalizada). `id_usuario` UNIQUE |
| piloto | Catálogo. `id_escuderia` = plantel de la semilla; NULL = libre |
| contrato | Pilotos de cada partida. UNIQUE (id_partida, id_piloto) |
| componentes | Catálogo: `costo`, `rendimiento_extra` (segundos), `durabilidad` (carreras) |
| compra | Ternaria partida–componente–carrera (`id_carrera` = antes de qué carrera se compró) |
| circuito | `tiempo_base` en segundos |
| carrera | `orden` 1 a 4. UNIQUE (id_temporada, orden) |
| resultado | Solo el **tiempo**. La posición y los puntos NO se guardan |
| puntos_por_posicion | Referencia (1° = 25 … 10° = 1) |

| Regla marcada (★) | Dónde se impone |
|---|---|
| El presupuesto nunca es negativo | `CHECK (presupuesto >= 0)` en partida |
| No se compra sin saldo suficiente | Procedimiento `sp_comprar_componente` (transacción) |
| Un piloto se contrata una sola vez por partida | `UNIQUE (id_partida, id_piloto)` en contrato |
| Cada usuario tiene una sola partida | `UNIQUE (id_usuario)` en partida |
| El tiempo es mayor a cero | `CHECK (tiempo > 0)` en resultado |
| La posición sale del tiempo | Vista `v_posiciones` (RANK) |
| Los puntos salen de la posición | Vista `v_puntos` + tabla `puntos_por_posicion` |
| Un resultado por piloto, carrera y partida | `UNIQUE (id_partida, id_carrera, id_piloto)` |

**Procedimientos** (devuelven una fila con la columna `resultado`):
- `sp_comprar_componente(p_partida, p_componente, p_carrera)`
- `sp_correr_carrera(p_partida)`: elige sola la siguiente carrera; si era la última, finaliza la partida.

**Vistas:** `v_posiciones`, `v_puntos` (columnas: id_partida, id_carrera, id_piloto, tiempo, es_jugador, posicion, puntos) y `v_ranking_usuarios` (nombre_usuario, escuderia, puntos_totales).

---

## 8. Lo que NO hay que hacer

- No cambiar tablas, columnas ni restricciones.
- No calcular en Python tiempos, posiciones, puntos ni validar el saldo.
- No llamar a `sp_correr_carrera` dentro del script SQL (usa `RAND()` y cambiaría los datos de prueba).
- No reordenar los INSERT de la semilla: los ids de pilotos y componentes se usan en los resultados y las compras.
- No volver a poner un selector de jugadores: el acceso es solo por login.
- No modificar datos a mano en phpMyAdmin: todo cambio va al script y se reimporta. El script es la única fuente de verdad.

---

## 9. Datos de prueba

| Usuario | Contraseña | Partida |
|---|---|---|
| sebastian | sebastian123 | Mercedes, temporada terminada (124 puntos) |
| lucia | lucia123 | Ferrari, 2 carreras corridas |
| martin | martin123 | McLaren, 32.000.000 y el Motor comprado (por la prueba de la transacción del script) |

Pilotos 1 a 12: rivales (2 por escudería). Pilotos 13 a 19: libres.

---

## 10. Limitaciones conocidas y mejoras futuras

- Contratar un piloto es una transacción en Python (INSERT + UPDATE); el saldo lo protege el CHECK. Mejora: un `sp_contratar_piloto` en la base que también controle el máximo de 2 pilotos.
- Las contraseñas usan SHA2 sin sal. Mejora: `bcrypt`.
- Una sola partida por usuario. Mejora: varias partidas.
- Contratar pilotos de escuderías rivales pagando una cláusula.

---

## 11. Entregables del Hito 4 (para tener presentes)

1. Código en el repositorio, con un README para instalar la base y jugar en una máquina limpia.
2. Una partida jugable de principio a fin con el script del Hito 3.
3. Informe de 2 a 3 páginas: cambios respecto del diseño, dónde se impone cada regla, mejoras futuras.
4. **Bitácora de uso de IA:** pedidos importantes, qué devolvió la IA y qué se corrigió o rechazó. No se califica la cantidad, sino el criterio.
