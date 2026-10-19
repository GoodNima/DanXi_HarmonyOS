import { Want } from '@kit.AbilityKit'
import { FormExtensionAbility, formBindingData, formInfo } from '@kit.FormKit'
import { CampusFormStore } from './CampusFormStore'

export default class CampusFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    CampusFormStore.init(this.context)
    const id = String(want.parameters?.[formInfo.FormParam.IDENTITY_KEY] ?? '')
    const feature = String(want.parameters?.[formInfo.FormParam.NAME_KEY] ?? 'timetable')
    const dimension = Number(want.parameters?.[formInfo.FormParam.DIMENSION_KEY] ?? 2)
    return formBindingData.createFormBindingData(JSON.stringify(CampusFormStore.add(id, feature, dimension)))
  }
  onUpdateForm(formId: string): void { CampusFormStore.init(this.context); CampusFormStore.update(formId) }
  onRemoveForm(formId: string): void { CampusFormStore.init(this.context); CampusFormStore.remove(formId) }
}
