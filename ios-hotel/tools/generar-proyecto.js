/**
 * Genera HotelApp.xcodeproj/project.pbxproj a partir de los .swift reales.
 *
 * Sustituye a `xcodegen` en Windows. Usa el formato "clásico" (objectVersion 56)
 * para que abra igual en Xcode 15 y 16. Las dependencias de Firebase/Facebook
 * se declaran como paquetes remotos SwiftPM, igual que en project.yml.
 *
 * Uso: node tools/generar-proyecto.js
 */
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const RAIZ = path.resolve(__dirname, '..');
const APP = path.join(RAIZ, 'HotelApp');
const SALIDA = path.join(RAIZ, 'HotelApp.xcodeproj');

// Un id estable por nombre: así regenerar no cambia el proyecto entero.
function oid(semilla) {
  return crypto.createHash('md5').update(semilla).digest('hex').slice(0, 24).toUpperCase();
}

function listar(dir, acc = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) {
      if (e.name.endsWith('.xcassets')) acc.push(p);
      else if (e.name !== 'xcuserdata') listar(p, acc);
    } else if (/\.(swift|png|jpg|jpeg|xib|storyboard|plist)$/.test(e.name)) {
      acc.push(p);
    }
  }
  return acc;
}

// Info.plist lo referencia INFOPLIST_FILE (no debe copiarse dos veces).
// GoogleService-Info.plist está en .gitignore: si el proyecto lo referenciara,
// un clon sin ese archivo fallaría con "Build input file cannot be found".
// La app funciona sin él (ver guarda en HotelApp.swift).
const archivos = listar(APP).filter(
  (p) => !p.endsWith(path.sep + 'Info.plist')
    && !p.endsWith(path.sep + 'GoogleService-Info.plist')
);

// --- Agrupar por carpeta para reproducir el árbol en Xcode ---------------
const grupos = new Map(); // ruta relativa -> { nombre, hijos:Set, archivos:[] }

function registrar(rel) {
  const partes = rel.split('/');
  for (let i = 1; i <= partes.length; i++) {
    const sub = partes.slice(0, i).join('/');
    const esArchivo = i === partes.length;
    if (!grupos.has(sub)) {
      grupos.set(sub, { nombre: partes[i - 1], hijos: new Set(), archivos: [] });
    }
    if (!esArchivo) {
      const padre = partes.slice(0, i - 1).join('/');
      if (padre && grupos.has(padre)) grupos.get(padre).hijos.add(sub);
    }
  }
  const carpeta = partes.slice(0, -1).join('/');
  if (carpeta && grupos.has(carpeta)) grupos.get(carpeta).archivos.push(rel);
}

for (const abs of archivos) registrar(path.relative(APP, abs).split(path.sep).join('/'));

const TIPO = {
  '.swift': 'sourcecode.swift',
  '.plist': 'text.plist.xml',
  '.json': 'text.json',
  '.png': 'image.png',
  '.jpg': 'image.jpeg',
  '.jpeg': 'image.jpeg',
  '.xcassets': 'folder.assetcatalog',
};

const ID_GRUPO_RAIZ = oid('grupo:HotelApp');
const ID_PRODUCTOS = oid('grupo:Products');
const ID_APP = oid('producto:Hotel.app');
const ID_TARGET = oid('target:HotelApp');
const ID_PROYECTO = oid('proyecto:HotelApp');
const ID_CONFIG_LISTA_PROYECTO = oid('cfglist:proyecto');
const ID_CONFIG_LISTA_TARGET = oid('cfglist:target');
const ID_FUENTES = oid('fase:fuentes');
const ID_RECURSOS = oid('fase:recursos');
const ID_FRAMEWORKS = oid('fase:frameworks');

const REF = {}; // rel -> {fileref, buildfile}
for (const abs of archivos) {
  const rel = path.relative(APP, abs).split(path.sep).join('/');
  REF[rel] = { fileref: oid('ref:' + rel), buildfile: oid('build:' + rel) };
}

// --- Dependencias SwiftPM ------------------------------------------------
const PAQUETES = [
  { clave: 'firebase', nombre: 'firebase-ios-sdk', url: 'https://github.com/firebase/firebase-ios-sdk', min: '11.0.0' },
  { clave: 'facebook', nombre: 'facebook-ios-sdk', url: 'https://github.com/facebook/facebook-ios-sdk', min: '17.0.0' },
];
const PRODUCTOS = [
  { paquete: 'firebase', producto: 'FirebaseCore' },
  { paquete: 'firebase', producto: 'FirebaseAuth' },
  { paquete: 'firebase', producto: 'FirebaseAnalytics' },
  { paquete: 'firebase', producto: 'FirebaseCrashlytics' },
  { paquete: 'facebook', producto: 'FacebookLogin' },
];

const idPaquete = (c) => oid('pkg:' + c);
const idProducto = (p) => oid('prod:' + p);

const lineas = [];
const push = (s = '') => lineas.push(s);

push('// !$*UTF8*$!');
push('{');
push('\tarchiveVersion = 1;');
push('\tclasses = {');
push('\t};');
push('\tobjectVersion = 56;');
push('\tobjects = {');
push('');

push('/* Begin PBXBuildFile section */');
for (const abs of archivos) {
  const rel = path.relative(APP, abs).split(path.sep).join('/');
  if (!rel.endsWith('.swift') && !rel.endsWith('.xcassets')) continue;
  const fase = rel.endsWith('.swift') ? 'Sources' : 'Resources';
  push(`\t\t${REF[rel].buildfile} /* ${path.basename(rel)} in ${fase} */ = {isa = PBXBuildFile; fileRef = ${REF[rel].fileref} /* ${path.basename(rel)} */; };`);
}
for (const p of PRODUCTOS) {
  push(`\t\t${oid('buildprod:' + p.producto)} /* ${p.producto} in Frameworks */ = {isa = PBXBuildFile; productRef = ${idProducto(p.producto)} /* ${p.producto} */; };`);
}
push('/* End PBXBuildFile section */');
push('');

push('/* Begin PBXFileReference section */');
for (const abs of archivos) {
  const rel = path.relative(APP, abs).split(path.sep).join('/');
  const nombre = path.basename(rel);
  const ext = path.extname(rel);
  const tipo = TIPO[ext] || 'text';
  push(`\t\t${REF[rel].fileref} /* ${nombre} */ = {isa = PBXFileReference; lastKnownFileType = ${tipo}; path = ${nombre}; sourceTree = "<group>"; };`);
}
push(`\t\t${ID_APP} /* Hotel.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Hotel.app; sourceTree = BUILT_PRODUCTS_DIR; };`);
push('/* End PBXFileReference section */');
push('');

push('/* Begin PBXFrameworksBuildPhase section */');
push(`\t\t${ID_FRAMEWORKS} /* Frameworks */ = {`);
push('\t\t\tisa = PBXFrameworksBuildPhase;');
push('\t\t\tbuildActionMask = 2147483647;');
push('\t\t\tfiles = (');
for (const p of PRODUCTOS) {
  push(`\t\t\t\t${oid('buildprod:' + p.producto)} /* ${p.producto} in Frameworks */,`);
}
push('\t\t\t);');
push('\t\t\trunOnlyForDeploymentPostprocessing = 0;');
push('\t\t};');
push('/* End PBXFrameworksBuildPhase section */');
push('');

// --- Grupos --------------------------------------------------------------
push('/* Begin PBXGroup section */');
const hijosDe = (ruta) => {
  const nodo = grupos.get(ruta);
  const hijos = [...(nodo ? nodo.hijos : [])].sort();
  const arch = nodo ? [...nodo.archivos].sort() : [];
  return { hijos, arch };
};

function emitirGrupo(ruta, nombre, indent) {
  const id = ruta === '' ? ID_GRUPO_RAIZ : oid('grupo:' + ruta);
  const { hijos, arch } = hijosDe(ruta);
  push(`${indent}${id}${ruta === '' ? ' = {' : ` /* ${nombre} */ = {`}`);
  push(`${indent}\tisa = PBXGroup;`);
  push(`${indent}\tchildren = (`);
  for (const h of hijos) {
    push(`${indent}\t\t${oid('grupo:' + h)} /* ${path.basename(h)} */,`);
  }
  for (const a of arch) {
    push(`${indent}\t\t${REF[a].fileref} /* ${path.basename(a)} */,`);
  }
  push(`${indent}\t);`);
  push(`${indent}\tpath = ${nombre};`);
  push(`${indent}\tsourceTree = "<group>";`);
  push(`${indent}};`);
  for (const h of hijos) {
    emitirGrupo(h, path.basename(h), indent);
  }
}

push('\t\t' + ID_GRUPO_RAIZ + ' /* HotelApp */ = {');
push('\t\t\tisa = PBXGroup;');
push('\t\t\tchildren = (');
{
  const { hijos, arch } = hijosDe('');
  for (const h of hijos) push(`\t\t\t\t${oid('grupo:' + h)} /* ${path.basename(h)} */,`);
  for (const a of arch) push(`\t\t\t\t${REF[a].fileref} /* ${path.basename(a)} */,`);
}
push('\t\t\t);');
push('\t\t\tpath = HotelApp;');
push('\t\t\tsourceTree = "<group>";');
push('\t\t};');
{
  const { hijos } = hijosDe('');
  for (const h of hijos) emitirGrupo(h, path.basename(h), '\t\t');
}
push(`\t\t${ID_PRODUCTOS} /* Products */ = {`);
push('\t\t\tisa = PBXGroup;');
push('\t\t\tchildren = (');
push(`\t\t\t\t${ID_APP} /* Hotel.app */,`);
push('\t\t\t);');
push('\t\t\tname = Products;');
push('\t\t\tsourceTree = "<group>";');
push('\t\t};');
const ID_RAIZ = oid('raiz');
push(`\t\t${ID_RAIZ} = {`);
push('\t\t\tisa = PBXGroup;');
push('\t\t\tchildren = (');
push(`\t\t\t\t${ID_GRUPO_RAIZ} /* HotelApp */,`);
push(`\t\t\t\t${ID_PRODUCTOS} /* Products */,`);
push('\t\t\t);');
push('\t\t\tsourceTree = "<group>";');
push('\t\t};');
push('/* End PBXGroup section */');
push('');

// --- Target / proyecto ---------------------------------------------------
push('/* Begin PBXNativeTarget section */');
push(`\t\t${ID_TARGET} /* HotelApp */ = {`);
push('\t\t\tisa = PBXNativeTarget;');
push(`\t\t\tbuildConfigurationList = ${ID_CONFIG_LISTA_TARGET} /* Build configuration list for PBXNativeTarget "HotelApp" */;`);
push('\t\t\tbuildPhases = (');
push(`\t\t\t\t${ID_FUENTES} /* Sources */,`);
push(`\t\t\t\t${ID_FRAMEWORKS} /* Frameworks */,`);
push(`\t\t\t\t${ID_RECURSOS} /* Resources */,`);
push('\t\t\t);');
push('\t\t\tbuildRules = (');
push('\t\t\t);');
push('\t\t\tdependencies = (');
push('\t\t\t);');
push('\t\t\tname = HotelApp;');
push('\t\t\tpackageProductDependencies = (');
for (const p of PRODUCTOS) push(`\t\t\t\t${idProducto(p.producto)} /* ${p.producto} */,`);
push('\t\t\t);');
push('\t\t\tproductName = Hotel;');
push(`\t\t\tproductReference = ${ID_APP} /* Hotel.app */;`);
push('\t\t\tproductType = "com.apple.product-type.application";');
push('\t\t};');
push('/* End PBXNativeTarget section */');
push('');

push('/* Begin PBXProject section */');
push(`\t\t${ID_PROYECTO} /* Project object */ = {`);
push('\t\t\tisa = PBXProject;');
push('\t\t\tattributes = {');
push('\t\t\t\tBuildIndependentTargetsInParallel = 1;');
push('\t\t\t\tLastSwiftUpdateCheck = 1500;');
push('\t\t\t\tLastUpgradeCheck = 1500;');
push('\t\t\t\tTargetAttributes = {');
push(`\t\t\t\t\t${ID_TARGET} = {`);
push('\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;');
push('\t\t\t\t\t};');
push('\t\t\t\t};');
push('\t\t\t};');
push(`\t\t\tbuildConfigurationList = ${ID_CONFIG_LISTA_PROYECTO} /* Build configuration list for PBXProject "HotelApp" */;`);
push('\t\t\tcompatibilityVersion = "Xcode 14.0";');
push('\t\t\tdevelopmentRegion = es;');
push('\t\t\thasScannedForEncodings = 0;');
push('\t\t\tknownRegions = (');
push('\t\t\t\tes,');
push('\t\t\t\ten,');
push('\t\t\t\tBase,');
push('\t\t\t);');
push(`\t\t\tmainGroup = ${ID_RAIZ};`);
push('\t\t\tpackageReferences = (');
for (const c of PAQUETES) push(`\t\t\t\t${idPaquete(c.clave)} /* XCRemoteSwiftPackageReference "${c.nombre}" */,`);
push('\t\t\t);');
push(`\t\t\tproductRefGroup = ${ID_PRODUCTOS} /* Products */;`);
push('\t\t\tprojectDirPath = "";');
push('\t\t\tprojectRoot = "";');
push('\t\t\ttargets = (');
push(`\t\t\t\t${ID_TARGET} /* HotelApp */,`);
push('\t\t\t);');
push('\t\t};');
push('/* End PBXProject section */');
push('');

push('/* Begin PBXResourcesBuildPhase section */');
push(`\t\t${ID_RECURSOS} /* Resources */ = {`);
push('\t\t\tisa = PBXResourcesBuildPhase;');
push('\t\t\tbuildActionMask = 2147483647;');
push('\t\t\tfiles = (');
for (const abs of archivos) {
  const rel = path.relative(APP, abs).split(path.sep).join('/');
  if (!rel.endsWith('.xcassets')) continue;
  push(`\t\t\t\t${REF[rel].buildfile} /* ${path.basename(rel)} in Resources */,`);
}
push('\t\t\t);');
push('\t\t\trunOnlyForDeploymentPostprocessing = 0;');
push('\t\t};');
push('/* End PBXResourcesBuildPhase section */');
push('');

push('/* Begin PBXSourcesBuildPhase section */');
push(`\t\t${ID_FUENTES} /* Sources */ = {`);
push('\t\t\tisa = PBXSourcesBuildPhase;');
push('\t\t\tbuildActionMask = 2147483647;');
push('\t\t\tfiles = (');
for (const abs of archivos) {
  const rel = path.relative(APP, abs).split(path.sep).join('/');
  if (!rel.endsWith('.swift')) continue;
  push(`\t\t\t\t${REF[rel].buildfile} /* ${path.basename(rel)} in Sources */,`);
}
push('\t\t\t);');
push('\t\t\trunOnlyForDeploymentPostprocessing = 0;');
push('\t\t};');
push('/* End PBXSourcesBuildPhase section */');
push('');

const COMUNES = {
  ALWAYS_SEARCH_USER_PATHS: 'NO',
  CLANG_ENABLE_MODULES: 'YES',
  CLANG_ENABLE_OBJC_ARC: 'YES',
  ENABLE_STRICT_OBJC_MSGSEND: 'YES',
  ENABLE_USER_SCRIPT_SANDBOXING: 'YES',
  GCC_C_LANGUAGE_STANDARD: 'gnu17',
  GCC_NO_COMMON_BLOCKS: 'YES',
  IPHONEOS_DEPLOYMENT_TARGET: '17.0',
  SDKROOT: 'iphoneos',
  SWIFT_VERSION: '5.9',
};
const TARGET = {
  ASSETCATALOG_COMPILER_APPICON_NAME: 'AppIcon',
  CODE_SIGN_STYLE: 'Automatic',
  DEVELOPMENT_TEAM: 'G48CMF53GY',
  GENERATE_INFOPLIST_FILE: 'NO',
  INFOPLIST_FILE: 'HotelApp/Info.plist',
  IPHONEOS_DEPLOYMENT_TARGET: '17.0',
  LD_RUNPATH_SEARCH_PATHS: '(\n\t\t\t\t\t"$(inherited)",\n\t\t\t\t\t"@executable_path/Frameworks",\n\t\t\t\t)',
  OTHER_LDFLAGS: '(\n\t\t\t\t\t"-ObjC",\n\t\t\t\t)',
  PRODUCT_BUNDLE_IDENTIFIER: 'pe.agrocorp.hotel',
  PRODUCT_NAME: 'Hotel',
  SUPPORTS_MACCATALYST: 'NO',
  SWIFT_EMIT_LOC_STRINGS: 'YES',
  TARGETED_DEVICE_FAMILY: '1',
};

function emitirConfig(id, nombre, ajustes) {
  push(`\t\t${id} /* ${nombre} */ = {`);
  push('\t\t\tisa = XCBuildConfiguration;');
  push('\t\t\tbuildSettings = {');
  for (const [k, v] of Object.entries(ajustes)) {
    push(v.startsWith('(') ? `\t\t\t\t${k} = ${v};` : `\t\t\t\t${k} = ${v};`);
  }
  push('\t\t\t};');
  push(`\t\t\tname = ${nombre};`);
  push('\t\t};');
}

push('/* Begin XCBuildConfiguration section */');
emitirConfig(oid('cfg:proyecto:Debug'), 'Debug', {
  ...COMUNES,
  DEBUG_INFORMATION_FORMAT: 'dwarf',
  ENABLE_TESTABILITY: 'YES',
  GCC_DYNAMIC_NO_PIC: 'NO',
  GCC_OPTIMIZATION_LEVEL: '0',
  GCC_PREPROCESSOR_DEFINITIONS: '(\n\t\t\t\t\t"DEBUG=1",\n\t\t\t\t\t"$(inherited)",\n\t\t\t\t)',
  MTL_ENABLE_DEBUG_INFO: 'INCLUDE_SOURCE',
  ONLY_ACTIVE_ARCH: 'YES',
  SWIFT_ACTIVE_COMPILATION_CONDITIONS: '"DEBUG $(inherited)"',
  SWIFT_OPTIMIZATION_LEVEL: '"-Onone"',
});
emitirConfig(oid('cfg:proyecto:Release'), 'Release', {
  ...COMUNES,
  DEBUG_INFORMATION_FORMAT: '"dwarf-with-dsym"',
  ENABLE_NS_ASSERTIONS: 'NO',
  MTL_ENABLE_DEBUG_INFO: 'NO',
  SWIFT_COMPILATION_MODE: 'wholemodule',
  VALIDATE_PRODUCT: 'YES',
});
emitirConfig(oid('cfg:target:Debug'), 'Debug', TARGET);
emitirConfig(oid('cfg:target:Release'), 'Release', TARGET);
push('/* End XCBuildConfiguration section */');
push('');

push('/* Begin XCConfigurationList section */');
push(`\t\t${ID_CONFIG_LISTA_PROYECTO} /* Build configuration list for PBXProject "HotelApp" */ = {`);
push('\t\t\tisa = XCConfigurationList;');
push('\t\t\tbuildConfigurations = (');
push(`\t\t\t\t${oid('cfg:proyecto:Debug')} /* Debug */,`);
push(`\t\t\t\t${oid('cfg:proyecto:Release')} /* Release */,`);
push('\t\t\t);');
push('\t\t\tdefaultConfigurationIsVisible = 0;');
push('\t\t\tdefaultConfigurationName = Release;');
push('\t\t};');
push(`\t\t${ID_CONFIG_LISTA_TARGET} /* Build configuration list for PBXNativeTarget "HotelApp" */ = {`);
push('\t\t\tisa = XCConfigurationList;');
push('\t\t\tbuildConfigurations = (');
push(`\t\t\t\t${oid('cfg:target:Debug')} /* Debug */,`);
push(`\t\t\t\t${oid('cfg:target:Release')} /* Release */,`);
push('\t\t\t);');
push('\t\t\tdefaultConfigurationIsVisible = 0;');
push('\t\t\tdefaultConfigurationName = Release;');
push('\t\t};');
push('/* End XCConfigurationList section */');
push('');

push('/* Begin XCRemoteSwiftPackageReference section */');
for (const c of PAQUETES) {
  push(`\t\t${idPaquete(c.clave)} /* XCRemoteSwiftPackageReference "${c.nombre}" */ = {`);
  push('\t\t\tisa = XCRemoteSwiftPackageReference;');
  push(`\t\t\trepositoryURL = "${c.url}";`);
  push('\t\t\trequirement = {');
  push('\t\t\t\tkind = upToNextMajorVersion;');
  push(`\t\t\t\tminimumVersion = ${c.min};`);
  push('\t\t\t};');
  push('\t\t};');
}
push('/* End XCRemoteSwiftPackageReference section */');
push('');

push('/* Begin XCSwiftPackageProductDependency section */');
for (const p of PRODUCTOS) {
  const c = PAQUETES.find((x) => x.clave === p.paquete);
  push(`\t\t${idProducto(p.producto)} /* ${p.producto} */ = {`);
  push('\t\t\tisa = XCSwiftPackageProductDependency;');
  push(`\t\t\tpackage = ${idPaquete(c.clave)} /* XCRemoteSwiftPackageReference "${c.nombre}" */;`);
  push(`\t\t\tproductName = ${p.producto};`);
  push('\t\t};');
}
push('/* End XCSwiftPackageProductDependency section */');
push('\t};');
push(`\trootObject = ${ID_PROYECTO} /* Project object */;`);
push('}');

fs.mkdirSync(SALIDA, { recursive: true });
fs.writeFileSync(path.join(SALIDA, 'project.pbxproj'), lineas.join('\n') + '\n', 'utf8');

// workspace interno mínimo: Xcode lo regenera, pero ayuda a abrir limpio.
const ws = path.join(SALIDA, 'project.xcworkspace');
fs.mkdirSync(ws, { recursive: true });
fs.writeFileSync(path.join(ws, 'contents.xcworkspacedata'),
  '<?xml version="1.0" encoding="UTF-8"?>\n<Workspace\n   version = "1.0">\n   <FileRef\n      location = "self:">\n   </FileRef>\n</Workspace>\n', 'utf8');

console.log(`project.pbxproj generado con ${archivos.length} recursos y ${archivos.filter((a) => a.endsWith('.swift')).length} archivos Swift.`);
