/*
 * Copyright (c) 2026 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * Adapted for this project to initialize app appearance and the chat page.
 */

import { Configuration, ConfigurationConstant, UIAbility } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

export default class EntryAbility extends UIAbility {
  onCreate(): void {
    this.updateAppearance(this.context.config);
  }

  onConfigurationUpdate(configuration: Configuration): void {
    this.updateAppearance(configuration);
  }

  private updateAppearance(configuration: Configuration): void {
    AppStorage.setOrCreate('systemDark', configuration.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    if (configuration.language) {
      AppStorage.setOrCreate('systemEnglish', !configuration.language.startsWith('zh'));
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    const storage = new LocalStorage();
    storage.setOrCreate('mainWindow', windowStage.getMainWindowSync());
    windowStage.loadContent('pages/Index', storage, (error) => {
      if (error.code) {
        hilog.error(0, 'DeepSeekNative', 'Could not load chat page: %{public}d', error.code);
      }
    });
  }
}
