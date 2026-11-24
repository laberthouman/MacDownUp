import unittest
from update_catalog import merge, parse_distribution, generation, catalog_urls, is_apple, newest_installers

DIST = '''<installer-gui-script><title>macOS Future</title><auxinfo><dict>
<key>macOSProductVersion</key><string>28.1</string>
<key>macOSProductBuildVersion</key><string>27B100</string>
</dict></auxinfo><script>var supportedDeviceIDs = ['Mac18,1', 'Mac18,2'];</script></installer-gui-script>'''


class CatalogTests(unittest.TestCase):
    def test_stable_metadata(self):
        result = parse_distribution(DIST)
        self.assertEqual(result['version'], '28.1')
        self.assertEqual(result['modelIDs'], ['Mac18,1', 'Mac18,2'])

    def test_beta_is_ignored(self):
        with self.assertRaises(ValueError):
            parse_distribution(DIST.replace('27B100', '27B100a'))
        with self.assertRaises(ValueError):
            parse_distribution(DIST.replace('macOS Future', 'macOS Future Beta'))

    def test_new_generation_and_existing_patch(self):
        original = {'schemaVersion': 1, 'revision': 1, 'releases': [
            {'id': '27', 'number': '27', 'year': 2026, 'finalVersion': '27.2.1', 'sources': []},
            {'id': '10.0', 'number': '10.0', 'year': 2001, 'finalVersion': '10.0.4', 'sources': []}]}
        record = dict(parse_distribution(DIST), url='https://swcdn.apple.com/InstallAssistant.pkg', year=2027)
        result = merge(original, {'28': record})
        self.assertEqual({r['id'] for r in result['releases']}, {'28', '27', '10.0'})
        self.assertEqual(result['releases'][0]['finalVersion'], '28.1')
        self.assertEqual(result['releases'][0]['sources'][0]['url'], record['url'])
        self.assertEqual(original['releases'][0]['finalVersion'], '27.2.1')

    def test_no_downgrade(self):
        original = {'releases': [{'id': '27', 'number': '27', 'year': 2026, 'finalVersion': '27.2.1', 'sources': []}]}
        record = dict(parse_distribution(DIST), version='27.1', url='https://swcdn.apple.com/InstallAssistant.pkg', year=2026)
        self.assertEqual(merge(original, {'27': record}), original)

    def test_realistic_product_detection(self):
        import datetime
        def product(url):
            return {'ExtendedMetaInfo': {'InstallAssistantPackageIdentifiers': {'SharedSupport': 'com.apple.pkg.InstallAssistant.macOS'}},
                    'Packages': [{'URL': url}], 'Distributions': {'English': 'https://swcdn.apple.com/installer.dist'},
                    'PostDate': datetime.datetime(2027, 10, 1)}
        products = {'valid': product('http://swcdn.apple.com/InstallAssistant.pkg'),
                    'invalid': product('https://apple.com.evil.test/InstallAssistant.pkg')}
        found = newest_installers(products, reader=lambda _: DIST.encode())
        self.assertEqual(set(found), {'28'})
        self.assertEqual(found['28']['url'], 'https://swcdn.apple.com/InstallAssistant.pkg')

    def test_catalog_future_years(self):
        self.assertIn('index-29-28-27-26-15', next(catalog_urls(2028)))
        self.assertEqual(generation('10.15.7'), '10.15')
        self.assertFalse(is_apple('https://apple.com.evil.test/pkg'))
        self.assertTrue(is_apple('https://updates.cdn-apple.com/pkg'))


if __name__ == '__main__':
    unittest.main()
