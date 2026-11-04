Respaldos de Gata Maula
Este repositorio es PRIVADO y guarda una copia diaria de toda la base de datos de la app (Supabase). No lo hagas publico nunca: tiene sueldos, horas, facturas y los usuarios de la app.

Que hay adentro
datos/estructura.sql: las tablas, funciones, permisos y triggers de la app.
datos/datos.sql: todos los datos (facturas, caja, stock, recetas, horas, sueldos, ventas...) y los usuarios con los que se entra.
datos/conteos.txt: cuantas filas tiene cada tabla ese dia.
datos/ultimo-respaldo.txt: fecha y hora de la ultima copia.
Cada dia se suma un commit nuevo (pestana Commits del repo). El historial guarda todos los dias: se puede volver a cualquiera. Si alguna vez falla la copia, GitHub te manda un mail. Revisa que ultimo-respaldo.txt tenga una fecha de hoy o de ayer.

Preparacion (se hace una sola vez)
Crear este repositorio en github.com como Private.
Crear el archivo .github/workflows/respaldo-diario.yml con el contenido de respaldo-diario.yml.
En Supabase: boton Connect (arriba) > pestana Session pooler > copiar la URL. Reemplazar [YOUR-PASSWORD] por la clave de la base (Project Settings > Database > Reset database password si no la sabes; usa solo letras y numeros; resetearla no afecta a la app).
En este repo: Settings > Secrets and variables > Actions > New repository secret. Nombre: SUPABASE_DB_URL. Valor: la URL del paso 3.
Pestana Actions > "Respaldo diario" > Run workflow. Tiene que quedar en verde y aparecer la carpeta datos.
Activar la verificacion en dos pasos en tu cuenta de GitHub (Settings > Password and authentication).
Como restaurar (si se perdio todo)
Esto lo conviene hacer con ayuda (Claude Code puede hacerlo en minutos). Los pasos son:

Crear un proyecto nuevo en Supabase.
Bajar este repositorio (boton verde Code > Download ZIP) y, si hace falta volver a un dia anterior, elegir ese commit en el historial.
Con psql y la URL del proyecto nuevo:
psql "URL_NUEVA" -f datos/estructura.sql
(echo "set session_replication_role = replica;"; cat datos/datos.sql) | psql "URL_NUEVA" (la primera linea apaga los triggers para que no vuelvan a mover el stock mientras se cargan los datos)
En Vercel, cambiar las variables de entorno de Supabase por las del proyecto nuevo.
Verificar contra datos/conteos.txt que cada tabla tenga la misma cantidad de filas.
La extension unaccent (y pg_trgm si estaba) tiene que existir en el proyecto nuevo: create extension if not exists unaccent with schema extensions;.
