import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/connectivity_service.dart';
import '../services/notification_service.dart';
import '../services/recipe_creation_service.dart';
import '../services/recipe_generator_service.dart';
import '../services/supabase_service.dart';
import '../services/transcript_service.dart';

final supabaseServiceProvider = Provider<SupabaseService>(
  (_) => SupabaseService.instance,
);

final transcriptServiceProvider = Provider<TranscriptService>(
  (_) => TranscriptService.instance,
);

final recipeGeneratorServiceProvider = Provider<RecipeGeneratorService>(
  (_) => RecipeGeneratorService.instance,
);

/// Note: RecipeCreationService is stateful per creation session.
/// Screens needing an isolated session should construct their own instance
/// directly (as CreateRecipeScreen does). This provider exposes one for
/// dependency-injection and testing convenience.
final recipeCreationServiceProvider = Provider<RecipeCreationService>(
  (ref) => RecipeCreationService(
    transcriptService: ref.read(transcriptServiceProvider),
    generatorService: ref.read(recipeGeneratorServiceProvider),
    supabaseService: ref.read(supabaseServiceProvider),
  ),
);

final notificationServiceProvider = Provider<NotificationService>(
  (_) => NotificationService.instance,
);

final connectivityServiceProvider = Provider<ConnectivityService>(
  (_) => ConnectivityService.instance,
);
