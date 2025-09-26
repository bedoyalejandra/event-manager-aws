exports.handler = async (event) => {
  return {
    statusCode: 200,
    body: JSON.stringify({ 
      message: "Disable Event Lambda - Not implemented yet",
      function: "disable-event"
    })
  };
};