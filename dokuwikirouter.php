<?php
// Router for PHP's built-in web server. Apache would block these DokuWiki folders
// with .htaccess files, which the built-in server ignores, so they are blocked here.
$protected = '#^/(data|conf|bin|inc|vendor)(/|$)#i';
$raw = str_replace(chr(92), '/', rawurldecode(explode('?', $_SERVER['REQUEST_URI'], 2)[0]));
$parts = [];
foreach (explode('/', $raw) as $part) {
    if ($part === '..') {
        array_pop($parts);
        continue;
    }
    $part = preg_replace('#(::\$\w+|[\s.:]+)$#', '', $part);
    if ($part === '') {
        continue;
    }
    $parts[] = $part;
}
$path = '/' . implode('/', $parts);
$root = realpath($_SERVER['DOCUMENT_ROOT']);
$file = realpath($_SERVER['DOCUMENT_ROOT'] . $raw);
$relative = ($file !== false && $root !== false) ? str_replace(chr(92), '/', substr($file, strlen($root))) : '';
if (preg_match($protected, $path) || preg_match($protected, $relative) || preg_match('#/\.#', $raw)) {
    http_response_code(403);
    echo 'Forbidden';
    return true;
}
return false;
