# Simulador de Fórmula 1

Trabajo final de Informática 2. Es una base de datos relacional que sostiene un juego
de gestión de escudería, más una aplicación en Streamlit para jugarlo.
Las reglas del juego (saldo, tiempos, posiciones y puntos) viven en la base,
en procedimientos, vistas y restricciones. La aplicación solo las llama y muestra lo que devuelven.

## Requisitos

- **XAMPP** con MariaDB 10.2 o más nuevo (o MySQL 8.0.16 o más nuevo).
- **Python 3.11** o más nuevo.

## 0. Descargar el proyecto

**Opción A: con Git** (requiere tener [Git](https://git-scm.com/downloads) instalado)

En una terminal, ubicarse en la carpeta donde se quiere guardar el proyecto y ejecutar:

```
git clone https://github.com/Alvarezeli/simulador_f1.git
cd simulador_f1
```

`git clone` descarga una copia completa del repositorio.
`cd simulador_f1` entra a la carpeta descargada.
Todos los comandos que siguen se ejecutan desde esa carpeta.

**Opción B: sin Git**

1. Entrar a la página del repositorio en GitHub.
2. Presionar el botón verde **Code** y elegir **Download ZIP**.
3. Descomprimir el archivo y abrir una terminal dentro de la carpeta `simulador_f1-main`.

## 1. Instalar la base de datos

1. Abrir XAMPP e iniciar **Apache** y **MySQL**.
2. Entrar a phpMyAdmin: `http://localhost/phpmyadmin`.
3. Ir a la pestaña **Importar**, elegir el archivo `sql/simulador_f1.sql` y presionar **Importar**.
   El script borra la base `simulador_f1` si ya existe y la crea de nuevo con los datos de prueba.
4. Verificar que la base tenga, en la pestaña **Rutinas**, los procedimientos
   `sp_comprar_componente` y `sp_correr_carrera`.

## 2. Instalar las librerías de Python

En una terminal, dentro de la carpeta del proyecto:

```
pip install -r requirements.txt
```

## 3. Configurar la conexión

Copiar el archivo `.env.example` con el nombre `.env`:

```
copy .env.example .env
```

Con XAMPP recién instalado no hace falta cambiar nada: el usuario `root` viene sin contraseña.
Si tu MySQL usa otra contraseña, otro usuario u otro puerto, completalos en `.env`.
El archivo `.env` no se sube al repositorio.

## 4. Ejecutar el juego

```
streamlit run APP.py
```

Se abre el navegador en `http://localhost:8501`.

## Cómo se juega

1. En la pestaña **Crear cuenta**, elegir un nombre de usuario, una contraseña y una escudería.
   La partida arranca con 50.000.000 de presupuesto y sin pilotos.
2. En **Mercado y tienda**, contratar 2 pilotos libres.
3. Antes de cada carrera, se pueden comprar componentes que restan segundos al tiempo.
   Cada componente dura una cantidad limitada de carreras.
4. En **Carreras**, correr las 4 carreras de la temporada, de a una y en orden.
5. Al terminar la carrera 4, la partida finaliza. En **Ranking** se comparan los puntos de todos los usuarios.

Desde **Carreras** también se puede reiniciar la temporada para volver a empezar.

## Estructura del proyecto

```
simulador_f1/
├── APP.py              ← aplicación Streamlit
├── requirements.txt    ← librerías de Python
├── .env.example        ← plantilla de la conexión a la base
├── sql/
│   └── simulador_f1.sql ← script completo de la base (Hito 3)
└── docs/               ← MER, modelo relacional, informe y bitácora de IA
```

## Problemas comunes

- **"No se pudo conectar a la base":** revisar que MySQL esté iniciado en XAMPP
  y que los datos de `.env` sean correctos.
- **`ModuleNotFoundError`:** falta instalar las librerías (paso 2).
- **Error al importar el script:** la versión de MariaDB o MySQL es anterior a la requerida
  (el script usa CHECK y `RANK() OVER`).
- **Al recargar la página pide iniciar sesión otra vez:** es normal. La sesión se guarda
  mientras la pestaña está abierta; la partida no se pierde, porque está guardada en la base.
