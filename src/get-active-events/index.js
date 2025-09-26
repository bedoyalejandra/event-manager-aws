exports.handler = async (event) => {
  return {
    statusCode: 200,
    body: JSON.stringify({ 
      message: "Get Active Events Lambda - Not implemented yet",
      function: "get-active-events",
      events: []
    })
  };
};