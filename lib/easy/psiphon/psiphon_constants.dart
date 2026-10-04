// Psiphon's public bootstrap values (server-list drops and the keys that sign
// them). Every Psiphon client carries the same ones. Collected with reference to
// the MLMVPN projects (https://github.com/mlmvpn), see NOTICE-easy.md.

class PsiphonDrop {
  final String url;
  final bool skipVerify;
  final int onlyAfterAttempts;

  const PsiphonDrop(
    this.url, {
    required this.skipVerify,
    required this.onlyAfterAttempts,
  });
}

const String psiphonPropagationChannelId = 'FFFFFFFFFFFFFFFF';
const String psiphonSponsorId = '1111111111111111';

const List<PsiphonDrop> psiphonRemoteServerListDrops = [
  PsiphonDrop(
    'https://s3.amazonaws.com/psiphon/web/iohq-waa4-q4dt/server_list_compressed',
    skipVerify: false,
    onlyAfterAttempts: 0,
  ),
  PsiphonDrop(
    'https://www.gpallthingsnumberweather.com/web/iohq-waa4-q4dt/server_list_compressed',
    skipVerify: true,
    onlyAfterAttempts: 2,
  ),
  PsiphonDrop(
    'https://www.storagejsstrategiesfabulous.com/web/iohq-waa4-q4dt/server_list_compressed',
    skipVerify: true,
    onlyAfterAttempts: 2,
  ),
  PsiphonDrop(
    'https://www.diamondberlingamerplanet.com/web/iohq-waa4-q4dt/server_list_compressed',
    skipVerify: true,
    onlyAfterAttempts: 2,
  ),
];

const List<PsiphonDrop> psiphonObfuscatedServerListDrops = [
  PsiphonDrop(
    'https://s3.amazonaws.com/psiphon/web/iohq-waa4-q4dt/osl',
    skipVerify: false,
    onlyAfterAttempts: 0,
  ),
  PsiphonDrop(
    'https://www.gpallthingsnumberweather.com/web/iohq-waa4-q4dt/osl',
    skipVerify: true,
    onlyAfterAttempts: 2,
  ),
  PsiphonDrop(
    'https://www.storagejsstrategiesfabulous.com/web/iohq-waa4-q4dt/osl',
    skipVerify: true,
    onlyAfterAttempts: 2,
  ),
  PsiphonDrop(
    'https://www.diamondberlingamerplanet.com/web/iohq-waa4-q4dt/osl',
    skipVerify: true,
    onlyAfterAttempts: 2,
  ),
];

const String psiphonRemoteServerListSignatureKey =
    'MIICIDANBgkqhkiG9w0BAQEFAAOCAg0AMIICCAKCAgEAt7Ls+/39r+T6zNW7GiVp'
    'Jfzq/xvL9SBH5rIFnk0RXYEYavax3WS6HOD35eTAqn8AniOwiH+DOkvgSKF2caqk'
    '/y1dfq47Pdymtwzp9ikpB1C5OfAysXzBiwVJlCdajBKvBZDerV1cMvRzCKvKwRmv'
    'DmHgphQQ7WfXIGbRbmmk6opMBh3roE42KcotLFtqp0RRwLtcBRNtCdsrVsjiI1Lq'
    'z/lH+T61sGjSjQ3CHMuZYSQJZo/KrvzgQXpkaCTdbObxHqb6/+i1qaVOfEsvjoiy'
    'zTxJADvSytVtcTjijhPEV6XskJVHE1Zgl+7rATr/pDQkw6DPCNBS1+Y6fy7GstZA'
    'LQXwEDN/qhQI9kWkHijT8ns+i1vGg00Mk/6J75arLhqcodWsdeG/M/moWgqQAnlZ'
    'AGVtJI1OgeF5fsPpXu4kctOfuZlGjVZXQNW34aOzm8r8S0eVZitPlbhcPiR4gT/a'
    'SMz/wd8lZlzZYsje/Jr8u/YtlwjjreZrGRmG8KMOzukV3lLmMppXFMvl4bxv6YFE'
    'mIuTsOhbLTwFgh7KYNjodLj/LsqRVfwz31PgWQFTEPICV7GCvgVlPRxnofqKSjgT'
    'WI4mxDhBpVcATvaoBl1L/6WLbFvBsoAUBItWwctO2xalKxF5szhGm8lccoc5MZr8'
    'kfE0uxMgsxz4er68iCID+rsCAQM=';

const String psiphonServerEntrySignatureKey =
    'sHuUVTWaRyh5pZwy4UguSgkwmBe0EHtJJkoF5WrxmvA=';

const String psiphonExchangeObfuscationKey =
    'DpXzloJk1Hw6aSzmKKky0xcahsEHubch81Mi6K0XMlU=';

const List<String> psiphonAlternateDns = [
  '208.67.222.222:5353',
  '9.9.9.9:9953',
  '208.67.220.220:5353',
];
