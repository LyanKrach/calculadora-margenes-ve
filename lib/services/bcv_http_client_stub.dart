import 'package:http/http.dart' as http;

/// Cliente HTTP stub para Web (en Web no se realizan llamadas directas a bcv.org.ve por CORS).
http.Client createBcvDirectHttpClient() => http.Client();
