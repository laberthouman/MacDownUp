#!/usr/bin/env python3
"""Discover stable full installers from Apple's public Software Update catalogs.
Only the standard library is required. Existing generations are never removed.
"""
import argparse
import copy
import datetime as dt
import gzip
import html
import json
import re
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from html.parser import HTMLParser
import plistlib

APPLE_GUIDE = 'https://support.apple.com/102662'
WALLPAPER_ARCHIVE = 'https://512pixels.net/projects/default-mac-wallpapers-in-5k/'


def is_apple(url):
    parsed = urllib.parse.urlsplit(url)
    host = (parsed.hostname or '').lower()
    return parsed.scheme == 'https' and (host == 'apple.com' or host.endswith('.apple.com') or host.endswith('.cdn-apple.com'))


def apple_https(url):
    parsed = urllib.parse.urlsplit(url)
    secured = urllib.parse.urlunsplit(parsed._replace(scheme='https'))
    if not is_apple(secured):
        raise ValueError('Non-Apple URL in Apple metadata')
    return secured


def fetch(url, limit=32 * 1024 * 1024):
    request = urllib.request.Request(url, headers={'User-Agent': 'MacDownUp-Catalog/1.0'})
    with urllib.request.urlopen(request, timeout=30) as response:
        if is_apple(url) and not is_apple(response.geturl()):
            raise ValueError('Unexpected Apple redirect')
        data = response.read(limit + 1)
    if len(data) > limit:
        raise ValueError('Metadata exceeds size limit')
    return data


def catalog_urls(year=None):
    year = year or dt.datetime.now(dt.timezone.utc).year
    old = ['15', '14', '13', '12', '10.16', '10.15', '10.14', '10.13', '10.12', '10.11', '10.10', '10.9', 'mountainlion', 'lion', 'snowleopard', 'leopard']
    for highest in range(year - 2000 + 1, 25, -1):
        generations = [str(v) for v in range(highest, 25, -1)] + old
        yield 'https://swscan.apple.com/content/catalogs/others/index-' + '-'.join(generations) + '.merged-1.sucatalog'


def read_public_catalog():
    for url in catalog_urls():
        try:
            data = fetch(url)
            if data.startswith(b'\x1f\x8b'):
                data = gzip.decompress(data)
            result = plistlib.loads(data)
            if not isinstance(result.get('Products'), dict):
                raise ValueError('Missing Products')
            return result
        except urllib.error.HTTPError as error:
            if error.code != 404:
                raise
    raise RuntimeError('No current public Apple catalog found')


def version_key(value):
    if not re.fullmatch(r'\d+(?:\.\d+){0,3}', value):
        raise ValueError('Non-stable version')
    return tuple(int(part) for part in value.split('.'))


def generation(version):
    parts = version.split('.')
    return '.'.join(parts[:2]) if parts[0] == '10' else parts[0]


def plist_string(root, names):
    nodes = list(root.iter())
    for i, node in enumerate(nodes[:-1]):
        if node.tag == 'key' and node.text in names and nodes[i + 1].tag == 'string':
            return nodes[i + 1].text or ''
    return ''


def parse_distribution(text):
    from xml.etree import ElementTree as ET
    root = ET.fromstring(text)
    version = plist_string(root, {'macOSProductVersion', 'VERSION'})
    build = plist_string(root, {'macOSProductBuildVersion', 'BUILD'})
    title = plist_string(root, {'SU_TITLE'}) or root.findtext('title', '')
    variable = re.search(r'var\s+SU_TITLE\s*=\s*[\'\"]([^\'\"]+)', text)
    if title in ('SU_TITLE', '') and variable:
        title = variable.group(1)
    version_key(version)
    if not re.fullmatch(r'\d+[A-Z]\d+', build) or re.search(r'beta|seed|developer|release candidate', title, re.I):
        raise ValueError('Prerelease installer')
    supported = re.search(r'var\s+supportedDeviceIDs\s*=\s*\[([^]]*)\]', text)
    model_ids = sorted(set(re.findall(r'[\'\"]([^\'\"]+)[\'\"]', supported.group(1)))) if supported else []
    return {'version': version, 'build': build, 'title': html.unescape(title), 'modelIDs': model_ids}


def inspect_product(pair, reader=fetch):
    product_id, product = pair
    try:
        identifiers = product.get('ExtendedMetaInfo', {}).get('InstallAssistantPackageIdentifiers', {})
        if not (identifiers.get('OSInstall') == 'com.apple.mpkg.OSInstall' or identifiers.get('SharedSupport', '').startswith('com.apple.pkg.InstallAssistant')):
            return None
        package = next((p for p in product.get('Packages', []) if urllib.parse.urlsplit(p.get('URL', '')).path.endswith('/InstallAssistant.pkg')), None)
        if not package:
            return None
        distributions = product.get('Distributions', {})
        url = distributions.get('English') or distributions.get('en') or next(iter(distributions.values()), '')
        record = parse_distribution(reader(apple_https(url)).decode('utf-8'))
        record['url'] = apple_https(package['URL'])
        record['productID'] = product_id
        date = product.get('PostDate')
        record['year'] = date.year if date else dt.datetime.now(dt.timezone.utc).year
        return record
    except (ValueError, KeyError, StopIteration, urllib.error.URLError) as error:
        print(f'Skipped product {product_id}: {error}')
        return None


def newest_installers(products, reader=fetch):
    with ThreadPoolExecutor(max_workers=6) as pool:
        records = list(pool.map(lambda pair: inspect_product(pair, reader), products.items()))
    latest = {}
    for record in filter(None, records):
        key = generation(record['version'])
        if key not in latest or version_key(record['version']) > version_key(latest[key]['version']):
            latest[key] = record
    return latest


class WallpaperLinks(HTMLParser):
    def __init__(self):
        super().__init__()
        self.images = []

    def handle_starttag(self, tag, attrs):
        attributes = dict(attrs)
        if tag == 'img':
            url = attributes.get('data-src') or attributes.get('src', '')
            if urllib.parse.urlsplit(url).hostname == 'media.512pixels.net':
                self.images.append((attributes.get('alt', '').lower(), url))


def add_wallpaper(release, root, images, repository):
    path = root / 'wallpapers' / (release['id'] + '.jpg')
    if path.exists():
        return
    name = release['marketingName'].lower()
    match = next((url for alt, url in images if name in alt and not any(v in alt for v in ('dark', 'night'))), None)
    if match:
        try:
            data = fetch(match, limit=8 * 1024 * 1024)
            if data.startswith(b'\xff\xd8'):
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(data)
                release['wallpaperURL'] = f'https://raw.githubusercontent.com/{repository}/main/wallpapers/{release["id"]}.jpg'
        except (ValueError, urllib.error.URLError) as error:
            print(f'Wallpaper not yet available: {error}')


def merge(document, records):
    result = copy.deepcopy(document)
    releases = {release['id']: release for release in result['releases']}
    for key, record in records.items():
        previous = releases.get(key)
        if previous and version_key(record['version']) < version_key(previous['finalVersion']):
            continue
        if previous:
            release = previous
        else:
            title = re.sub(r'^(?:Install\s+)?(?:macOS|OS X)\s+', '', record['title'], flags=re.I).strip()
            name = title if title and title not in ('InstallAssistant', 'SU_TITLE') else key
            ids = record['modelIDs']
            release = {
                'id': key, 'marketingName': name, 'family': 'macOS', 'number': key,
                'finalVersion': record['version'], 'year': record['year'], 'detail': 'Новый стабильный выпуск из каталога Apple',
                'overview': f'Версия {record["version"]}, сборка {record["build"]}. Автоматически обнаружена в публичном каталоге Apple.',
                'architecture': 'См. совместимость Apple', 'installerMedia': 'InstallAssistant.pkg', 'isModern': True,
                'compatibility': {
                    'models': [{'family': 'Модели Apple', 'models': ', '.join(ids) if ids else 'Точный список ещё уточняется Apple. Проверьте совместимость перед установкой.'}],
                    'note': 'Для нового поколения показаны идентификаторы из установщика, если Apple их публикует. Полный список и названия моделей уточняются на сайте Apple.',
                    'reference': APPLE_GUIDE,
                }, 'sources': [],
            }
            releases[key] = release
        release['finalVersion'] = record['version']
        direct = {'id': f'direct-{key}', 'title': 'Прямая загрузка Apple',
                  'subtitle': f'InstallAssistant.pkg · {record["version"]} · {record["build"]}',
                  'kind': 'appleImage', 'url': record['url'], 'reference': APPLE_GUIDE}
        others = [source for source in release['sources'] if source['id'] != direct['id']]
        for source in others:
            if source['kind'] == 'softwareUpdate':
                source['version'] = record['version']
                source['subtitle'] = f'Полный установщик · {record["version"]}'
        release['sources'] = [direct] + others
    result['releases'] = sorted(releases.values(), key=lambda item: (item['year'], version_key(item['number'])), reverse=True)
    return result


def update(root, repository, reader=fetch):
    path = root / 'catalog.json'
    original = json.loads(path.read_text())
    if original.get('schemaVersion') != 1:
        raise ValueError('Unsupported catalog schema')
    records = newest_installers(read_public_catalog()['Products'], reader)
    if not records:
        raise RuntimeError('No stable installers found; keeping existing catalog')
    changed = merge(original, records)
    try:
        parser = WallpaperLinks()
        parser.feed(fetch(WALLPAPER_ARCHIVE).decode('utf-8'))
        images = parser.images
    except urllib.error.URLError:
        images = []
    for release in changed['releases']:
        add_wallpaper(release, root, images, repository)
    if changed['releases'] == original['releases']:
        print('No catalog changes')
        return False
    changed['revision'] = original['revision'] + 1
    changed['updatedAt'] = dt.datetime.now(dt.timezone.utc).isoformat().replace('+00:00', 'Z')
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(changed, ensure_ascii=False, indent=2) + '\n')
    temporary.replace(path)
    print(f'Wrote revision {changed["revision"]}: {len(changed["releases"])} generations')
    return True


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, default=Path('.'))
    parser.add_argument('--repository', default='laberthouman/MacDownUp')
    args = parser.parse_args()
    update(args.root, args.repository)
