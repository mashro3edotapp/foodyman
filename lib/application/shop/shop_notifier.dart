import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_share/flutter_share.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:riverpodtemp/domain/iterface/categories.dart';
import 'package:riverpodtemp/domain/iterface/products.dart';
import 'package:riverpodtemp/domain/iterface/shops.dart';
import 'package:riverpodtemp/infrastructure/models/models.dart';
import 'package:riverpodtemp/infrastructure/services/app_connectivity.dart';
import 'package:riverpodtemp/infrastructure/services/app_helpers.dart';
import 'package:riverpodtemp/infrastructure/services/local_storage.dart';
import 'package:http/http.dart' as http;
import 'package:riverpodtemp/infrastructure/services/marker_image_cropper.dart';
import '../../domain/iterface/draw.dart';
import '../../infrastructure/services/app_constants.dart';
import 'shop_state.dart';
import 'package:intl/intl.dart' as intl;

class ShopNotifier extends StateNotifier<ShopState> {
  final ProductsRepositoryFacade _productsRepository;
  final ShopsRepositoryFacade _shopsRepository;
  final CategoriesRepositoryFacade _categoriesRepository;
  final DrawRepositoryFacade _drawRouting;

  ShopNotifier(this._shopsRepository, this._productsRepository,
      this._categoriesRepository, this._drawRouting)
      : super(const ShopState());
  int page = 1;
  List<int> _list = [];
  String? shareLink;

  void showWeekTime() {
    state = state.copyWith(showWeekTime: !state.showWeekTime);
  }

  Future<void> getRoutingAll({
    required BuildContext context,
    required LatLng start,
    required LatLng end,
  }) async {
    if (await AppConnectivity.connectivity()) {
      state = state.copyWith(polylineCoordinates: []);
      final response = await _drawRouting.getRouting(start: start, end: end);
      response.when(
        success: (data) {
          List<LatLng> list = [];
          List ls = data.features[0].geometry.coordinates;
          for (int i = 0; i < ls.length; i++) {
            list.add(LatLng(ls[i][1], ls[i][0]));
          }
          state = state.copyWith(
            polylineCoordinates: list,
          );
        },
        failure: (failure, status) {
          state = state.copyWith(polylineCoordinates: []);
        },
      );
    } else {
      if (mounted) {
        AppHelpers.showNoConnectionSnackBar(context);
      }
    }
  }

  getMarker() async {
    state = state.copyWith(isMapLoading: true);
    final ImageCropperForMarker image = ImageCropperForMarker();
    Set<Marker> markers = {};
    markers.addAll({
      Marker(
          markerId: const MarkerId("shop"),
          position: LatLng(
            state.shopData?.location?.latitude ?? AppConstants.demoLatitude,
            state.shopData?.location?.longitude ?? AppConstants.demoLongitude,
          ),
          icon:
              await image.resizeAndCircle(state.shopData?.logoImg ?? "", 120)),
      Marker(
          markerId: const MarkerId("user"),
          position: LatLng(
            LocalStorage.instance.getAddressSelected()?.location?.latitude ??
                AppConstants.demoLatitude,
            LocalStorage.instance.getAddressSelected()?.location?.longitude ??
                AppConstants.demoLongitude,
          ),
          icon: await image.resizeAndCircle(
              LocalStorage.instance.getProfileImage(), 120))
    });
    state = state.copyWith(shopMarkers: markers, isMapLoading: false);
  }

  void onLike() {
    if (state.isLike) {
      for (int i = 0; i < _list.length; i++) {
        if (_list[i] == state.shopData?.id) {
          _list.removeAt(i);
          break;
        }
      }
    } else {
      _list.add(state.shopData?.id ?? 0);
    }
    state = state.copyWith(isLike: !state.isLike);
    LocalStorage.instance.setSavedShopsList(_list);
  }

  void changeIndex(int index) {
    state = state.copyWith(currentIndex: index);
  }

  void checkWorkingDay() {
    int todayWeekIndex = 0;
    for (int i = 0; i < state.shopData!.shopWorkingDays!.length; i++) {
      if (state.shopData!.shopWorkingDays![i].day ==
              intl.DateFormat("EEEE").format(DateTime.now()).toLowerCase() &&
          !(state.shopData!.shopWorkingDays![i].disabled ?? true)) {
        state = state.copyWith(isTodayWorkingDay: true);
        todayWeekIndex = i;
        break;
      } else {
        state = state.copyWith(isTodayWorkingDay: false);
      }
    }

    if (state.isTodayWorkingDay) {
      for (int i = 0; i < state.shopData!.shopClosedDate!.length; i++) {
        if (DateTime.now().year ==
                state.shopData!.shopClosedDate![i].day!.year &&
            DateTime.now().month ==
                state.shopData!.shopClosedDate![i].day!.month &&
            DateTime.now().day == state.shopData!.shopClosedDate![i].day!.day) {
          state = state.copyWith(isTodayWorkingDay: false);
          break;
        } else {
          state = state.copyWith(isTodayWorkingDay: true);
        }
      }
      if (state.isTodayWorkingDay) {
        TimeOfDay startTimeOfDay = TimeOfDay(
          hour: int.tryParse(state
                      .shopData!.shopWorkingDays?[todayWeekIndex].from
                      ?.substring(
                          0,
                          state.shopData!.shopWorkingDays?[todayWeekIndex].from
                                  ?.indexOf("-") ??
                              0) ??
                  "") ??
              0,
          minute: int.tryParse(state
                      .shopData!.shopWorkingDays?[todayWeekIndex].from
                      ?.substring((state.shopData!
                                  .shopWorkingDays?[todayWeekIndex].from
                                  ?.indexOf("-") ??
                              0) +
                          1) ??
                  "") ??
              0,
        );
        TimeOfDay endTimeOfDay = TimeOfDay(
          hour: int.tryParse(state.shopData!.shopWorkingDays?[todayWeekIndex].to
                      ?.substring(
                          0,
                          state.shopData!.shopWorkingDays?[todayWeekIndex].to
                                  ?.indexOf("-") ??
                              0) ??
                  "") ??
              0,
          minute: int.tryParse(state
                      .shopData!.shopWorkingDays?[todayWeekIndex].to
                      ?.substring((state
                                  .shopData!.shopWorkingDays?[todayWeekIndex].to
                                  ?.indexOf("-") ??
                              0) +
                          1) ??
                  "") ??
              0,
        );
        state = state.copyWith(
          startTodayTime: startTimeOfDay,
          endTodayTime: endTimeOfDay,
        );
      }
    }
  }

  Future<void> setShop(ShopData shop) async {
    _list = LocalStorage.instance.getSavedShopsList();
    for (int e in _list) {
      if (e == shop.id) {
        state = state.copyWith(
          isLike: true,
        );
        break;
      }
    }
    state = state.copyWith(
      shopData: shop,
    );
    generateShareLink();
    checkWorkingDay();
    final response =
        await _shopsRepository.getSingleShop(uuid: (shop.id ?? 0).toString());
    response.when(
      success: (data) async {
        _list = LocalStorage.instance.getSavedShopsList();
        for (int e in _list) {
          if (e == data.data?.id) {
            state = state.copyWith(
              isLike: true,
            );
            break;
          }
        }
        state = state.copyWith(
          shopData: data.data,
        );
        checkWorkingDay();
      },
      failure: (activeFailure, status) {},
    );
  }

  leaveGroup() {
    state = state.copyWith(
      userUuid: "",
      isGroupOrder: false,
    );
  }

  Future<void> joinOrder(BuildContext context, String shopId, String cartId,
      String name, VoidCallback onSuccess) async {
    final connected = await AppConnectivity.connectivity();
    if (connected) {
      state = state.copyWith(isJoinOrder: true);
      final response = await _shopsRepository.joinOrder(
          shopId: shopId, name: name, cartId: cartId);
      response.when(
        success: (data) async {
          state = state.copyWith(
              isJoinOrder: false, isGroupOrder: true, userUuid: data);
          onSuccess();
        },
        failure: (activeFailure, status) {
          state = state.copyWith(
            isJoinOrder: false,
            userUuid: "",
            isGroupOrder: false,
          );
        },
      );
    } else {
      if (mounted) {
        AppHelpers.showNoConnectionSnackBar(context);
      }
    }
  }

  Future<void> fetchShop(BuildContext context, String uuid) async {
    final connected = await AppConnectivity.connectivity();
    if (connected) {
      state = state.copyWith(isLoading: true);
      final response = await _shopsRepository.getSingleShop(uuid: uuid);
      response.when(
        success: (data) async {
          _list = LocalStorage.instance.getSavedShopsList();
          for (int e in _list) {
            if (e == data.data?.id) {
              state = state.copyWith(
                isLike: true,
              );
              break;
            }
          }
          state = state.copyWith(
            isLoading: false,
            shopData: data.data,
          );
          generateShareLink();
          checkWorkingDay();
        },
        failure: (activeFailure, status) {
          state = state.copyWith(isLoading: false);
          AppHelpers.showCheckTopSnackBar(
            context,
            AppHelpers.getTranslation(status.toString()),
          );
        },
      );
    } else {
      if (mounted) {
        AppHelpers.showNoConnectionSnackBar(context);
      }
    }
  }

  Future<bool> fetchCategory(BuildContext context, String shopId) async {
    final connected = await AppConnectivity.connectivity();
    if (connected) {
      state = state.copyWith(isCategoryLoading: true);
      final response =
          await _categoriesRepository.getCategoriesByShop(shopId: shopId);
      response.when(
        success: (data) async {
          state = state.copyWith(
            category: data.data,
            isCategoryLoading: false,
          );
          return true;
        },
        failure: (activeFailure, status) {
          state = state.copyWith(isCategoryLoading: false);
          AppHelpers.showCheckTopSnackBar(
            context,
            AppHelpers.getTranslation(status.toString()),
          );
          return false;
        },
      );
      return false;
    } else {
      if (mounted) {
        AppHelpers.showNoConnectionSnackBar(context);
      }
      return false;
    }
  }

  Future<void> fetchProducts(BuildContext context, String shopId) async {
    final connected = await AppConnectivity.connectivity();
    if (connected) {
      page = 1;
      state = state.copyWith(
        isProductLoading: true,
      );
      final response = await _productsRepository.getProductsPaginate(
          page: 1, shopId: shopId);
      response.when(
        success: (data) {
          state = state.copyWith(
            products: data.data ?? [],
            isProductLoading: false,
          );
        },
        failure: (failure, status) {
          state = state.copyWith(isProductLoading: false);
          AppHelpers.showCheckTopSnackBar(
            context,
            AppHelpers.getTranslation(status.toString()),
          );
        },
      );
    } else {
      if (mounted) {
        AppHelpers.showNoConnectionSnackBar(
          context,
        );
      }
    }
  }

  Future<void> checkProductsPopular(BuildContext context, String shopId) async {
    final connected = await AppConnectivity.connectivity();
    if (connected) {
      page = 1;
      state = state.copyWith(
        isPopularLoading: true,
      );
      final response = await _productsRepository.getProductsPopularPaginate(
          page: 1, shopId: shopId);
      response.when(
        success: (data) {
          state = state.copyWith(
              isPopularLoading: false,
              isPopularProduct: (data.data ?? []).isNotEmpty);
        },
        failure: (failure, status) {
          state = state.copyWith(isPopularLoading: false);
          AppHelpers.showCheckTopSnackBar(
            context,
            AppHelpers.getTranslation(status.toString()),
          );
        },
      );
    } else {
      if (mounted) {
        AppHelpers.showNoConnectionSnackBar(
          context,
        );
      }
    }
  }

  Future<void> fetchProductsPopular(BuildContext context, String shopId) async {
    final connected = await AppConnectivity.connectivity();
    if (connected) {
      page = 1;
      state = state.copyWith(
        isProductLoading: true,
      );
      final response = await _productsRepository.getProductsPopularPaginate(
          page: 1, shopId: shopId);
      response.when(
        success: (data) {
          state = state.copyWith(
              products: data.data ?? [],
              isProductLoading: false,
              isPopularProduct: (data.data ?? []).isNotEmpty);
        },
        failure: (failure, status) {
          state = state.copyWith(isProductLoading: false);
          AppHelpers.showCheckTopSnackBar(
            context,
            AppHelpers.getTranslation(status.toString()),
          );
        },
      );
    } else {
      if (mounted) {
        AppHelpers.showNoConnectionSnackBar(
          context,
        );
      }
    }
  }

  Future<void> fetchProductsByCategory(
      BuildContext context, String shopId, int categoryId) async {
    final connected = await AppConnectivity.connectivity();
    if (connected) {
      state = state.copyWith(
        isProductLoading: true,
      );
      page = 1;
      final response = await _productsRepository.getProductsByCategoryPaginate(
          page: 1, shopId: shopId, categoryId: categoryId);
      response.when(
        success: (data) {
          state = state.copyWith(
            products: data.data ?? [],
            isProductLoading: false,
          );
        },
        failure: (failure, status) {
          state = state.copyWith(isProductLoading: false);
          AppHelpers.showCheckTopSnackBar(
            context,
            AppHelpers.getTranslation(status.toString()),
          );
        },
      );
    } else {
      if (mounted) {
        AppHelpers.showNoConnectionSnackBar(
          context,
        );
      }
    }
  }

  Future<void> fetchProductsByCategoryPage(
      BuildContext context, String shopId, int categoryId) async {
    final connected = await AppConnectivity.connectivity();
    if (connected) {
      state = state.copyWith(
        isProductPageLoading: true,
      );
      final response = await _productsRepository.getProductsByCategoryPaginate(
          page: ++page, shopId: shopId, categoryId: categoryId);
      response.when(
        success: (data) {
          List<ProductData> list = List.from(state.products);
          list.addAll(data.data!.toList());
          state = state.copyWith(
            products: list,
            isProductPageLoading: false,
          );
        },
        failure: (failure, status) {
          state = state.copyWith(isProductPageLoading: false);
          AppHelpers.showCheckTopSnackBar(
            context,
            AppHelpers.getTranslation(status.toString()),
          );
        },
      );
    } else {
      if (mounted) {
        AppHelpers.showNoConnectionSnackBar(
          context,
        );
      }
    }
  }

  Future<void> fetchProductsPage(BuildContext context, String shopId) async {
    final connected = await AppConnectivity.connectivity();
    if (connected) {
      state = state.copyWith(
        isProductPageLoading: true,
      );
      final response = await _productsRepository.getProductsPaginate(
          page: ++page, shopId: shopId);
      response.when(
        success: (data) {
          List<ProductData> list = List.from(state.products);
          list.addAll(data.data!.toList());
          state = state.copyWith(
            products: list,
            isProductPageLoading: false,
          );
        },
        failure: (failure, status) {
          state = state.copyWith(isProductPageLoading: false);
          AppHelpers.showCheckTopSnackBar(
            context,
            AppHelpers.getTranslation(status.toString()),
          );
        },
      );
    } else {
      if (mounted) {
        AppHelpers.showNoConnectionSnackBar(
          context,
        );
      }
    }
  }

  Future<void> fetchProductsPopularPage(
      BuildContext context, String shopId) async {
    final connected = await AppConnectivity.connectivity();
    if (connected) {
      state = state.copyWith(
        isProductPageLoading: true,
      );
      final response = await _productsRepository.getProductsPopularPaginate(
          page: ++page, shopId: shopId);
      response.when(
        success: (data) {
          List<ProductData> list = List.from(state.products);
          list.addAll(data.data!.toList());
          state = state.copyWith(
            products: list,
            isProductPageLoading: false,
          );
        },
        failure: (failure, status) {
          state = state.copyWith(isProductPageLoading: false);
          AppHelpers.showCheckTopSnackBar(
            context,
            AppHelpers.getTranslation(status.toString()),
          );
        },
      );
    } else {
      if (mounted) {
        AppHelpers.showNoConnectionSnackBar(
          context,
        );
      }
    }
  }

  generateShareLink() async {
    final productLink =
        '${AppConstants.webUrl}/${state.shopData?.type}/${state.shopData?.id}';

    const dynamicLink =
        'https://firebasedynamiclinks.googleapis.com/v1/shortLinks?key=AIzaSyDraEPokcqncELQIoXO2Phy0YZUUIaKqMI';

    final dataShare = {
      "dynamicLinkInfo": {
        "domainUriPrefix": 'https://foodyman.page.link',
        "link": productLink,
        "androidInfo": {
          "androidPackageName": 'com.foodyman',
          "androidFallbackLink":
              "${AppConstants.webUrl}/${state.shopData?.type}/${state.shopData?.id}"
        },
        "iosInfo": {
          "iosBundleId": "com.foodyman.customer",
          "iosFallbackLink":
              "${AppConstants.webUrl}/${state.shopData?.type}/${state.shopData?.id}"
        },
        "socialMetaTagInfo": {
          "socialTitle": "${state.shopData?.translation?.title}",
          "socialDescription": "${state.shopData?.translation?.description}",
          "socialImageLink": '${state.shopData?.logoImg}',
        }
      }
    };

    final res =
        await http.post(Uri.parse(dynamicLink), body: jsonEncode(dataShare));

    shareLink = jsonDecode(res.body)['shortLink'];
  }

  onShare() async {
    await FlutterShare.share(
      text: state.shopData?.translation?.title ?? "Foodyman",
      title: state.shopData?.translation?.description ?? "",
      linkUrl: shareLink,
    );
  }
}
