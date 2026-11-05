import 'package:supabase_flutter/supabase_flutter.dart';

class ServicoPagamento {
  static final _supabase = Supabase.instance.client;

  // 1. Cobrança via Pix
  static Future<Map<String, dynamic>?> gerarPix({
    required String cpf,
    required String nome,
    required double valor,
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'efi-pagamentos',
        body: {
          'action': 'gerar-pix',
          'cpf': cpf,
          'nome': nome,
          'valor': valor,
          'expiracao': 3600,
        },
      );

      if (response.status == 200) {
        return response.data as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      print('Erro ao gerar Pix: $e');
      return null;
    }
  }

  // 2. Cobrança via Cartão / Planos (Preparado para expansão)
  static Future<Map<String, dynamic>?> cobrarCartao({
    required String tokenCartao,
    required double valor,
    required String planoId,
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'efi-pagamentos',
        body: {
          'action': 'cobrar-cartao',
          'token_cartao': tokenCartao,
          'valor': valor,
          'plano_id': planoId,
        },
      );

      if (response.status == 200) {
        return response.data as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      print('Erro ao processar cartão: $e');
      return null;
    }
  }
}
