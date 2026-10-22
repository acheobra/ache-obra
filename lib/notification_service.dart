import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationService {
  static final FirebaseMessaging _firebaseMessaging =
      FirebaseMessaging.instance;

  static final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static const String _tabelaUsuarios = 'tab_usuarios';
  static const String _colunaPushAtivo = 'push_ativo';
  static const String _colunaFcmToken = 'fcm_token';

  static bool _listenerTokenConfigurado = false;
  static bool _listenerForegroundConfigurado = false;

  static Future<void> initialize() async {
    // ============================================================
    // 1. INICIALIZA NOTIFICAÇÃO LOCAL
    // ============================================================

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings(
      'ic_notification',
    );

    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await _localNotificationsPlugin.initialize(
      initializationSettings,
    );

    // ============================================================
    // 2. RESPEITA A PREFERÊNCIA DO USUÁRIO
    // ============================================================

    final bool pushAtivo = await isPushEnabled();

    if (!pushAtivo) {
      try {
        await _firebaseMessaging.setAutoInitEnabled(
          false,
        );

        await _firebaseMessaging.deleteToken();

        await _limparTokenNoBanco();
      } catch (e) {
        print(
          'Erro ao manter Push desativado: $e',
        );
      }
    } else {
      await _ativarFirebaseMessaging();
    }

    // ============================================================
    // 3. TOKEN REFRESH
    // ============================================================

    if (!_listenerTokenConfigurado) {
      _listenerTokenConfigurado = true;

      _firebaseMessaging.onTokenRefresh.listen(
        (newToken) async {
          final bool permitido = await isPushEnabled();

          if (permitido) {
            await _saveTokenToDatabase(
              newToken,
            );
          }
        },
      );
    }

    // ============================================================
    // 4. NOTIFICAÇÃO COM APP ABERTO
    // ============================================================

    if (!_listenerForegroundConfigurado) {
      _listenerForegroundConfigurado = true;

      FirebaseMessaging.onMessage.listen(
        (RemoteMessage message) async {
          final bool permitido = await isPushEnabled();

          if (!permitido) {
            return;
          }

          final RemoteNotification? notification = message.notification;

          final AndroidNotification? android = message.notification?.android;

          if (notification != null && android != null) {
            _localNotificationsPlugin.show(
              notification.hashCode,
              notification.title,
              notification.body,
              const NotificationDetails(
                android: AndroidNotificationDetails(
                  'canal_principal',
                  'Notificações Gerais',
                  channelDescription:
                      'Canal para alertas importantes do Ache Obra',
                  importance: Importance.max,
                  priority: Priority.high,
                  icon: 'ic_notification',
                ),
              ),
            );
          }
        },
      );
    }
  }

  // ============================================================
  // CONSULTA PREFERÊNCIA DO USUÁRIO
  // ============================================================

  static Future<bool> isPushEnabled() async {
    final user = Supabase.instance.client.auth.currentUser;

    // Sem usuário logado não existe preferência individual para ler.
    // Mantém true para não alterar o comportamento de login/cadastro.
    if (user == null) {
      return true;
    }

    try {
      final data = await Supabase.instance.client
          .from(_tabelaUsuarios)
          .select(
            _colunaPushAtivo,
          )
          .eq(
            'id',
            user.id,
          )
          .maybeSingle();

      if (data == null) {
        return true;
      }

      final valor = data[_colunaPushAtivo];

      // Compatibilidade com usuários existentes antes da criação da coluna.
      if (valor == null) {
        return true;
      }

      return valor == true;
    } catch (e) {
      print(
        'Erro ao consultar preferência Push: $e',
      );

      // Em caso de falha de leitura, não remove o token do usuário.
      return true;
    }
  }

  // ============================================================
  // ALTERA PREFERÊNCIA PELO APP
  // ============================================================

  static Future<bool> setPushEnabled(
    bool enabled,
  ) async {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) {
      return false;
    }

    try {
      if (enabled) {
        // Salva primeiro a preferência.
        await Supabase.instance.client.from(_tabelaUsuarios).update({
          _colunaPushAtivo: true,
        }).eq(
          'id',
          user.id,
        );

        final bool ativado = await _ativarFirebaseMessaging();

        if (!ativado) {
          // Se o sistema operacional negar a permissão,
          // volta a preferência para desativado.
          await Supabase.instance.client.from(_tabelaUsuarios).update({
            _colunaPushAtivo: false,
            _colunaFcmToken: null,
          }).eq(
            'id',
            user.id,
          );

          return false;
        }

        return true;
      }

      // ==========================================================
      // DESATIVAR
      // ==========================================================

      await Supabase.instance.client.from(_tabelaUsuarios).update({
        _colunaPushAtivo: false,
        _colunaFcmToken: null,
      }).eq(
        'id',
        user.id,
      );

      await _firebaseMessaging.setAutoInitEnabled(
        false,
      );

      try {
        await _firebaseMessaging.deleteToken();
      } catch (e) {
        print(
          'Aviso ao excluir token FCM: $e',
        );
      }

      return true;
    } catch (e) {
      print(
        'Erro ao alterar preferência Push: $e',
      );

      return false;
    }
  }

  // ============================================================
  // ATIVA FIREBASE MESSAGING
  // ============================================================

  static Future<bool> _ativarFirebaseMessaging() async {
    try {
      await _firebaseMessaging.setAutoInitEnabled(
        true,
      );

      final NotificationSettings settings =
          await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      final bool autorizado =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
              settings.authorizationStatus == AuthorizationStatus.provisional;

      if (!autorizado) {
        print(
          'Permissão de notificação negada pelo usuário.',
        );

        return false;
      }

      print(
        'Permissão de notificação concedida!',
      );

      await updateFcmToken();

      return true;
    } catch (e) {
      print(
        'Erro ao ativar Firebase Messaging: $e',
      );

      return false;
    }
  }

  // ============================================================
  // BUSCA TOKEN ATUAL
  // ============================================================

  static Future<void> updateFcmToken() async {
    try {
      final bool permitido = await isPushEnabled();

      if (!permitido) {
        await _limparTokenNoBanco();
        return;
      }

      final String? token = await _firebaseMessaging.getToken();

      if (token != null && token.trim().isNotEmpty) {
        await _saveTokenToDatabase(
          token,
        );
      }
    } catch (e) {
      print(
        'Erro ao obter token FCM: $e',
      );
    }
  }

  // ============================================================
  // SALVA TOKEN NO SUPABASE
  // ============================================================

  static Future<void> _saveTokenToDatabase(
    String token,
  ) async {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) {
      return;
    }

    try {
      final bool permitido = await isPushEnabled();

      if (!permitido) {
        await _limparTokenNoBanco();
        return;
      }

      await Supabase.instance.client.from(_tabelaUsuarios).update({
        _colunaFcmToken: token,
      }).eq(
        'id',
        user.id,
      );

      print(
        'Token FCM salvo com sucesso no Supabase!',
      );
    } catch (e) {
      print(
        'Erro ao salvar token FCM no Supabase: $e',
      );
    }
  }

  // ============================================================
  // REMOVE TOKEN DA TABELA
  // ============================================================

  static Future<void> _limparTokenNoBanco() async {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) {
      return;
    }

    try {
      await Supabase.instance.client.from(_tabelaUsuarios).update({
        _colunaFcmToken: null,
      }).eq(
        'id',
        user.id,
      );
    } catch (e) {
      print(
        'Erro ao limpar token FCM no Supabase: $e',
      );
    }
  }
}
