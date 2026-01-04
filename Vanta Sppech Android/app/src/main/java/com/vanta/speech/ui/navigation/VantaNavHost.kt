package com.vanta.speech.ui.navigation

import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Stream
import androidx.compose.material.icons.outlined.Folder
import androidx.compose.material.icons.outlined.Mic
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.Stream
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.vanta.speech.R
import com.vanta.speech.core.auth.AuthenticationManager
import com.vanta.speech.feature.auth.LoginScreen
import com.vanta.speech.feature.library.LibraryScreen
import com.vanta.speech.feature.library.RecordingDetailScreen
import com.vanta.speech.feature.realtime.RealtimeRecordingScreen
import com.vanta.speech.feature.recording.RecordingScreen
import com.vanta.speech.feature.settings.EWSCalendarSettingsScreen
import com.vanta.speech.feature.settings.OutlookCalendarSettingsScreen
import com.vanta.speech.feature.settings.SettingsScreen
import com.vanta.speech.ui.theme.VantaColors
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject

data class BottomNavItem(
    val screen: Screen,
    val labelResId: Int,
    val selectedIcon: ImageVector,
    val unselectedIcon: ImageVector
)

private val bottomNavItems = listOf(
    BottomNavItem(
        screen = Screen.Recording,
        labelResId = R.string.nav_recording,
        selectedIcon = Icons.Filled.Mic,
        unselectedIcon = Icons.Outlined.Mic
    ),
    BottomNavItem(
        screen = Screen.Realtime,
        labelResId = R.string.nav_realtime,
        selectedIcon = Icons.Filled.Stream,
        unselectedIcon = Icons.Outlined.Stream
    ),
    BottomNavItem(
        screen = Screen.Library,
        labelResId = R.string.nav_library,
        selectedIcon = Icons.Filled.Folder,
        unselectedIcon = Icons.Outlined.Folder
    ),
    BottomNavItem(
        screen = Screen.Settings,
        labelResId = R.string.nav_settings,
        selectedIcon = Icons.Filled.Settings,
        unselectedIcon = Icons.Outlined.Settings
    )
)

@HiltViewModel
class NavHostViewModel @Inject constructor(
    val authManager: AuthenticationManager
) : ViewModel()

@Composable
fun VantaNavHost(
    viewModel: NavHostViewModel = hiltViewModel()
) {
    val navController = rememberNavController()
    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentDestination = navBackStackEntry?.destination
    val isAuthenticated by viewModel.authManager.isAuthenticated.collectAsStateWithLifecycle()

    // Determine start destination based on auth state
    val startDestination = if (isAuthenticated) Screen.Recording.route else Screen.Login.route

    val showBottomBar = bottomNavItems.any { item ->
        currentDestination?.hierarchy?.any { it.route == item.screen.route } == true
    }

    Scaffold(
        bottomBar = {
            if (showBottomBar) {
                NavigationBar(
                    containerColor = VantaColors.DarkSurface
                ) {
                    bottomNavItems.forEach { item ->
                        val selected = currentDestination?.hierarchy?.any {
                            it.route == item.screen.route
                        } == true

                        NavigationBarItem(
                            selected = selected,
                            onClick = {
                                navController.navigate(item.screen.route) {
                                    popUpTo(navController.graph.findStartDestination().id) {
                                        saveState = true
                                    }
                                    launchSingleTop = true
                                    restoreState = true
                                }
                            },
                            icon = {
                                Icon(
                                    imageVector = if (selected) item.selectedIcon else item.unselectedIcon,
                                    contentDescription = stringResource(item.labelResId)
                                )
                            },
                            label = {
                                Text(text = stringResource(item.labelResId))
                            },
                            colors = NavigationBarItemDefaults.colors(
                                selectedIconColor = VantaColors.PinkVibrant,
                                selectedTextColor = VantaColors.PinkVibrant,
                                unselectedIconColor = VantaColors.DarkTextSecondary,
                                unselectedTextColor = VantaColors.DarkTextSecondary,
                                indicatorColor = VantaColors.PinkVibrant.copy(alpha = 0.2f)
                            )
                        )
                    }
                }
            }
        }
    ) { innerPadding ->
        NavHost(
            navController = navController,
            startDestination = startDestination,
            modifier = Modifier.padding(innerPadding)
        ) {
            composable(Screen.Login.route) {
                LoginScreen(
                    onLoginSuccess = {
                        navController.navigate(Screen.Recording.route) {
                            popUpTo(Screen.Login.route) { inclusive = true }
                        }
                    }
                )
            }
            composable(Screen.Recording.route) {
                RecordingScreen()
            }
            composable(Screen.Realtime.route) {
                RealtimeRecordingScreen(
                    onRecordingCompleted = { recordingId ->
                        navController.navigate(Screen.RecordingDetail.createRoute(recordingId)) {
                            popUpTo(Screen.Realtime.route) { inclusive = true }
                        }
                    }
                )
            }
            composable(Screen.Library.route) {
                LibraryScreen(
                    onRecordingClick = { recordingId ->
                        navController.navigate(Screen.RecordingDetail.createRoute(recordingId))
                    }
                )
            }
            composable(Screen.Settings.route) {
                SettingsScreen(
                    onNavigateToOutlook = {
                        navController.navigate(Screen.OutlookSettings.route)
                    },
                    onNavigateToEWS = {
                        navController.navigate(Screen.EWSSettings.route)
                    }
                )
            }
            composable(Screen.OutlookSettings.route) {
                OutlookCalendarSettingsScreen(
                    onNavigateBack = { navController.popBackStack() }
                )
            }
            composable(Screen.EWSSettings.route) {
                EWSCalendarSettingsScreen(
                    onNavigateBack = { navController.popBackStack() }
                )
            }
            composable(Screen.RecordingDetail.route) { backStackEntry ->
                val recordingId = backStackEntry.arguments?.getString("recordingId") ?: return@composable
                RecordingDetailScreen(
                    recordingId = recordingId,
                    onNavigateBack = { navController.popBackStack() }
                )
            }
        }
    }
}
