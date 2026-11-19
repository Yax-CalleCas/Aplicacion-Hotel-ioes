/**
 * Verificador ligero de Swift para Windows.
 *
 * No sustituye a `swiftc` ni a Xcode: comprueba que cada archivo tenga
 * llaves, paréntesis y corchetes balanceados, que no queden marcadores
 * pendientes y que las estructuras de nivel superior estén bien cerradas.
 *
 * Uso:  node tools/verificar-sintaxis.js
 */
const fs = require('fs');
const path = require('path');

const RAIZ = path.resolve(__dirname, '..', 'HotelApp');

function archivosSwift(dir, acc = []) {
  for (const entrada of fs.readdirSync(dir, { withFileTypes: true })) {
    const ruta = path.join(dir, entrada.name);
    if (entrada.isDirectory()) archivosSwift(ruta, acc);
    else if (entrada.name.endsWith('.swift')) acc.push(ruta);
  }
  return acc;
}

/** Elimina comentarios y cadenas para no contar símbolos dentro de ellos. */
function limpiar(codigo) {
  let salida = '';
  let i = 0;
  let enBloque = false;

  while (i < codigo.length) {
    const dos = codigo.slice(i, i + 2);

    if (enBloque) {
      if (dos === '*/') { enBloque = false; i += 2; continue; }
      if (codigo[i] === '\n') salida += '\n';
      i++;
      continue;
    }

    if (dos === '/*') { enBloque = true; i += 2; continue; }

    if (dos === '//') {
      while (i < codigo.length && codigo[i] !== '\n') i++;
      continue;
    }

    // Cadenas simples y multilínea
    if (codigo[i] === '"') {
      const triple = codigo.slice(i, i + 3) === '"""';
      const cierre = triple ? '"""' : '"';
      i += cierre.length;
      while (i < codigo.length) {
        if (codigo[i] === '\\') { i += 2; continue; }
        if (codigo.slice(i, i + cierre.length) === cierre) {
          i += cierre.length;
          break;
        }
        if (!triple && codigo[i] === '\n') break; // cadena sin cerrar
        i++;
      }
      salida += '""';
      continue;
    }

    salida += codigo[i];
    i++;
  }
  return salida;
}

function verificar(ruta) {
  const original = fs.readFileSync(ruta, 'utf8');
  const codigo = limpiar(original);
  const problemas = [];

  const pares = { '}': '{', ')': '(', ']': '[' };
  const pila = [];
  let linea = 1;

  for (let i = 0; i < codigo.length; i++) {
    const c = codigo[i];
    if (c === '\n') { linea++; continue; }

    if (c === '{' || c === '(' || c === '[') {
      pila.push({ c, linea });
    } else if (c in pares) {
      const tope = pila.pop();
      if (!tope || tope.c !== pares[c]) {
        problemas.push(`L${linea}: '${c}' sin cierre correspondiente`);
        return problemas;
      }
    }
  }

  if (pila.length > 0) {
    const tope = pila[pila.length - 1];
    problemas.push(`L${tope.linea}: '${tope.c}' quedó sin cerrar`);
  }

  // Marcadores prohibidos por el contrato del proyecto.
  // Se buscan como palabra completa para no confundir "TODOS" con "TODO".
  for (const marcador of ['TODO', 'FIXME', 'NotImplementedError']) {
    const patron = new RegExp(`\\b${marcador}\\b`);
    if (patron.test(original)) {
      problemas.push(`Contiene marcador pendiente: ${marcador}`);
    }
  }

  // Todo archivo debe declarar al menos un tipo o función de nivel superior.
  if (!/^(import |@main|final class |struct |enum |actor |extension |protocol )/m.test(codigo)) {
    problemas.push('No declara ningún tipo o función de nivel superior');
  }

  return problemas;
}

function main() {
  const archivos = archivosSwift(RAIZ);
  let errores = 0;

  for (const archivo of archivos) {
    const problemas = verificar(archivo);
    const relativa = path.relative(RAIZ, archivo);

    if (problemas.length === 0) {
      console.log(`  OK   ${relativa}`);
    } else {
      errores++;
      console.log(`  FAIL ${relativa}`);
      for (const p of problemas) console.log(`       ${p}`);
    }
  }

  console.log(`\n${archivos.length} archivos Swift, ${errores} con problemas.`);
  process.exit(errores === 0 ? 0 : 1);
}

main();
