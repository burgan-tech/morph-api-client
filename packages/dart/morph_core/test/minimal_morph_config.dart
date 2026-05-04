/// Shared minimal Morph JSON for tests (parity with `config_and_morph_client_test`).
Map<String, dynamic> minimalValidConfig() => {
      'providers': [
        {
          'key': 'p',
          'type': 'oauth2',
          'baseUrl': 'https://issuer.example',
          'contexts': [
            {
              'key': 'c',
              'token': {'endpoint': '/token'},
              'tokenTypes': {
                'access': {
                  'expiryPolicy': 'token',
                  'storage': {
                    'scope': 's',
                    'type': 'memory',
                    'protection': 'secure',
                    'key': 'access-key',
                  },
                },
              },
            },
          ],
        },
      ],
      'hosts': [
        {
          'key': 'api',
          'baseUrl': 'https://api.example',
          'allowedAuth': ['p/c'],
        },
      ],
    };
