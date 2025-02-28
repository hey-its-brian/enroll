var Verification = (function(){
   var target_id = function(target){
       return target.replace("v-action-", "");
   };
   function showVerifyType(target){
       $('#'+target_id(target)).fadeIn('slow');
   }
   function showReturnForDef(target){
       $('#'+target_id(target)+'-return').fadeIn('slow');
   }
   function showHubCall(target){
       $('#'+target_id(target)+'-hub').fadeIn('slow');
   }

   function showExtendAction(target) {
       $('#'+target_id(target)+'-extend').fadeIn('slow');

       const dueOnSelectLabel = $('.extend-request #due-on-options')
       const dueOnSelect = dueOnSelectLabel.find('select');
       const dueOnDateLabel = $('.extend-request label#manual-due-on');
       const dueOnDate = dueOnDateLabel.find('input[type="date"]');

       function toggleManualDate(isManual) {
          if (isManual) {
             dueOnSelectLabel.addClass('hidden');
             dueOnSelect.attr('disabled', true);

             dueOnDateLabel.removeClass('hidden');
             dueOnDate.removeAttr('disabled');
          } else {
             dueOnSelectLabel.removeClass('hidden');
             dueOnSelect.removeAttr('disabled');
     
             dueOnDateLabel.addClass('hidden');
             dueOnDate.attr('disabled', true);
          }
       }
       
       dueOnSelect.val('');
       toggleManualDate(false);
       dueOnSelect.off('change').on('change', function(){
          if($(this).val() === 'manual'){
             toggleManualDate(true);
          }
       });
   }

   function showViewHistory(target) {
       $('#'+target_id(target)+'-history').fadeIn('slow');
   }
   function hideAllActions(target){
       hideVerifyAction(target);
       hideReturnForDef(target);
       hideHubCall(target);
       hideExtendAction(target);
   }
   function hideVerifyAction(target){
       $('#'+target_id(target)).hide();
   }
   function hideReturnForDef(target){
       $('#'+target_id(target)+'-return').hide();
   }
   function hideHubCall(target){
       $('#'+target_id(target)+'-hub').hide();
   }
   function hideExtendAction(target){
       $('#'+target_id(target)+'-extend').hide();
   }
   function confirmVerificationType(){
       $(this).closest('div').parent().hide();
   }
   function checkAction(event){
     var $selected_id = $(event.target).attr('id');
     var $selected_el = $('#'+$selected_id);
     var $selected_el_val = $selected_el.val();

     switch ($selected_el_val) {
         case 'Verify':
             hideAllActions($selected_id);
             showVerifyType($selected_id);
             break;
         case 'Reject':
             hideAllActions($selected_id);
             showReturnForDef($selected_id);
             break;
         case 'Call HUB':
             hideAllActions($selected_id);
             showHubCall($selected_id);
             break;
         case 'Extend':
         case "Set due date":
            hideAllActions($selected_id);
            showExtendAction($selected_id);
            break;
         case 'View History':
             hideAllActions($selected_id);
             showViewHistory($selected_id);
             break;
         default:
             hideAllActions($selected_id);
     }
   }

   return {
       show_update: showVerifyType,
       check_selected_action: checkAction,
       confirm_v_type: confirmVerificationType
   }
})();

$(document).on("ready turbolinks:load", function() {
   $('.v-type-actions').on('change', Verification.check_selected_action);
   $('.verification-update-reason').delegate('a', "click", Verification.confirm_v_type );
});
